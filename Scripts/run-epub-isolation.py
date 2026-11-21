#!/usr/bin/env python3
"""Run focused EPUB isolation tests while observing macOS DNS traffic."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
READY_TIMEOUT_SECONDS = 20
TEST_TIMEOUT_SECONDS = 20 * 60
CHILD_SHUTDOWN_SECONDS = 10
TCPDUMP = "/usr/sbin/tcpdump"
FILTER = "port 53 or udp port 5353"
INTERFACE = re.compile(r"^([A-Za-z][\w.-]*): flags=([0-9a-fA-F]+)(?:<[^>]*>)?(?=\s|$)")
# Ordinary link types with IP decoders; metadata taps are not permitted.
LINK_TYPES = {"EN10MB", "NULL", "LOOP", "RAW", "IPV4", "IPV6", "PPP", "IEEE802_11", "IEEE802_11_RADIO"}
STATS = re.compile(r"^(\d+) packets? (captured|received by filter|dropped by kernel|dropped by interface)$")
MARKER = re.compile(
    r"\b(bookreader-(control|strict)-[0-9a-f-]+\.example\.com)\b", re.IGNORECASE
)
FOCUSED_TEST = "-only-testing:BookReaderTests/EPUBIsolationTests"


class CaptureError(RuntimeError):
    pass


RUN_ERRORS = (CaptureError, OSError, subprocess.SubprocessError)


def macos_command(*command):
    return subprocess.run(
        command, stdin=subprocess.DEVNULL, capture_output=True, text=True,
        encoding="utf-8", errors="replace", env={**os.environ, "LC_ALL": "C"},
        timeout=CHILD_SHUTDOWN_SECONDS,
    )


def network_snapshot():
    result = macos_command("/sbin/ifconfig", "-a")
    if result.returncode or result.stderr.strip():
        raise CaptureError(f"ifconfig failed (exit {result.returncode}): {result.stderr.strip()}")
    active = set()
    interface = None
    up = False
    for line in result.stdout.splitlines():
        if line and not line[0].isspace():
            header = INTERFACE.match(line)
            if not header:
                raise CaptureError("could not parse an ifconfig interface header")
            interface = header[1]
            up = bool(int(header[2], 16) & 1)  # IFF_UP, not media status or IFF_RUNNING
        elif up and re.match(r"^\s+inet6?\s", line):
            active.add(interface)
    if not active:
        raise CaptureError("ifconfig found no UP IPv4/IPv6 interfaces")

    routes = {}
    for family, option in (("ipv4", "-inet"), ("ipv6", "-inet6")):
        result = macos_command("/sbin/route", "-n", "get", option, "default")
        stderr = result.stderr.strip()
        matches = re.findall(r"^\s*interface:[ \t]+(\S+)[ \t]*$", result.stdout, re.MULTILINE)
        # Darwin route get can return 0 even when there is no default route.
        if not matches and stderr in {
            "route: writing to routing socket: not in table",
            "route: message indicates error 3: No such process",
        }:
            routes[family] = None
        elif result.returncode or stderr or len(matches) != 1:
            raise CaptureError(f"could not determine {family} default route (exit {result.returncode}): {stderr}")
        else:
            routes[family] = matches[0]
    return {"interfaces": sorted(active), "default_route_interfaces": routes}


def require_default_coverage(snapshot):
    for family, interface in snapshot["default_route_interfaces"].items():
        if interface is not None and interface not in snapshot["interfaces"]:
            raise CaptureError(f"{family} default route uses uncovered interface {interface}")


class Capture:
    def __init__(self, interface, sudo, log_file, log_lock):
        self.interface = interface
        self.sudo = sudo
        self.log_file = log_file
        self.log_lock = log_lock
        self.ready = threading.Event()
        self.process = None
        self.readers = []
        self.eof = set()
        self.early_exit = False
        self.control_seen = False
        self.strict_seen = False
        self.link_type = None
        self.stats = {}
        self.errors = []

    def start(self):
        self.process = subprocess.Popen(
            [self.sudo, "-n", TCPDUMP, "-i", self.interface, "-p", "-B", "16384",
             "--immediate-mode", "-l", "-nn", "-s", "0", "-vvv", FILTER],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", bufsize=1, start_new_session=True,
            env={**os.environ, "LC_ALL": "C"},
        )
        for stream, name in ((self.process.stdout, "stdout"), (self.process.stderr, "stderr")):
            reader = threading.Thread(target=self._read_stream, args=(stream, name), daemon=True)
            reader.start()
            self.readers.append(reader)

    def _read_stream(self, stream, name):
        try:
            with stream:
                for line in stream:
                    if name == "stderr":
                        self._read_status(line.strip())
                    else:
                        for hostname, kind in MARKER.findall(line):
                            if kind.lower() == "control":
                                self.control_seen = True
                            else:
                                self.strict_seen = True
                            with self.log_lock:
                                print(f"{self.interface}: {hostname.lower()}", file=self.log_file, flush=True)
            self.eof.add(name)
        except (OSError, ValueError) as exc:
            self.errors.append(f"capture {name} reader failed: {exc}")

    def _read_status(self, line):
        prefix = f"tcpdump: listening on {self.interface}, link-type "
        if line.startswith(prefix):
            self.link_type = line[len(prefix):].partition(" ")[0]
            if self.link_type not in LINK_TYPES:
                self.errors.append(f"unsupported capture link type: {self.link_type!r}")
            else:
                self.ready.set()
        elif stats := STATS.fullmatch(line):
            key = stats[2]
            if key in self.stats:
                self.errors.append(f"duplicate tcpdump statistic: {key}")
            self.stats[key] = int(stats[1])
        elif line:
            self.errors.append(line)

    def _signal_group(self, signum):
        # SIGKILL must reach privileged members too; sudo cannot relay it.
        if signum != signal.SIGKILL:
            try:
                os.killpg(self.process.pid, signum)
                return
            except ProcessLookupError:
                return
            except PermissionError:
                pass
        result = macos_command(
            self.sudo, "-n", "/bin/kill", "-s", signum.name[3:], "--", f"-{self.process.pid}",
        )
        if result.returncode:
            try:
                os.killpg(self.process.pid, 0)
            except ProcessLookupError:
                return
            except PermissionError:
                pass
            raise CaptureError(f"owned capture group did not accept {signum.name}: {result.stderr.strip()}")

    def _try_signal(self, signum):
        try:
            self._signal_group(signum)
        except RUN_ERRORS as exc:
            self.errors.append(str(exc))

    def request_stop(self):
        if self.process is not None:
            if self.process.poll() is None:
                self._try_signal(signal.SIGINT)
            else:
                self.early_exit = True

    def finish(self):
        if self.process is None:
            return
        for signum, timeout in ((None, CHILD_SHUTDOWN_SECONDS), (signal.SIGTERM, 3), (signal.SIGKILL, 3)):
            if signum is not None:
                self.errors.append(f"tcpdump did not shut down; escalating to {signum.name}")
                self._try_signal(signum)
            try:
                self.process.wait(timeout=timeout)
                break
            except subprocess.TimeoutExpired:
                continue
        else:
            self.errors.append("tcpdump did not exit after shutdown")

        deadline = time.monotonic() + CHILD_SHUTDOWN_SECONDS
        for reader in self.readers:
            reader.join(timeout=max(0, deadline - time.monotonic()))
        if any(reader.is_alive() for reader in self.readers):
            self.errors.append("capture output did not reach EOF within shutdown deadline")
            self._try_signal(signal.SIGKILL)

    def result(self):
        exit_code = self.process.returncode if self.process is not None else None
        drops = self.stats.get("dropped by kernel")
        # tcpdump prints the interface drop statistic only when nonzero.
        interface_drops = self.stats.get("dropped by interface", 0) if drops is not None else None
        drained = self.eof == {"stdout", "stderr"}
        errors = list(self.errors)
        if not self.ready.is_set():
            errors.append("tcpdump never reported readiness")
        if not drained:
            errors.append("capture output did not drain both streams to EOF")
        if self.early_exit:
            errors.append("tcpdump exited before shutdown was requested")
        if exit_code != 0:
            errors.append(f"tcpdump exit status: {exit_code}")
        if drops is None:
            errors.append("tcpdump kernel drop count was unavailable")
        elif drops or interface_drops:
            errors.append("tcpdump reported dropped packets")
        return {
            "ready": self.ready.is_set(), "link_type": self.link_type,
            "output_drained": drained, "capture_exit_code": exit_code,
            "capture_exited_early": self.early_exit, "capture_errors": errors,
            "kernel_dropped_packets": drops, "interface_dropped_packets": interface_drops,
            "captured_packets": self.stats.get("captured"),
            "received_by_filter": self.stats.get("received by filter"),
            "control_dns_observed": self.control_seen, "strict_dns_observed": self.strict_seen,
        }


def stop_process_group(process):
    if process is None or process.poll() is not None:
        return
    for signum, timeout in ((signal.SIGTERM, CHILD_SHUTDOWN_SECONDS), (signal.SIGKILL, 3)):
        try:
            os.killpg(process.pid, signum)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=timeout)
            return
        except subprocess.TimeoutExpired:
            continue
    raise CaptureError("focused xcodebuild did not exit after shutdown")


def main(argv):
    if "--" not in argv:
        print("usage: run-epub-isolation.py -- xcodebuild ...", file=sys.stderr)
        return 2
    command = argv[argv.index("--") + 1 :]
    if not command or Path(command[0]).name != "xcodebuild" or FOCUSED_TEST not in command:
        print(f"expected xcodebuild with {FOCUSED_TEST}", file=sys.stderr)
        return 2

    diagnostics = ROOT / "build" / "diagnostics"
    diagnostics.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc)
    run_id = now.strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}"
    log_path = diagnostics / f"epub-isolation-tcpdump-{run_id}.log"
    summary_path = diagnostics / f"epub-isolation-{run_id}.json"
    captures = {}
    before = after = None
    log_file = test_process = None
    timed_out = False
    interrupted = None
    errors = []

    def interrupt(signum, _frame):
        nonlocal interrupted
        # Do not throw asynchronously while starting or cleaning up an owned child.
        if interrupted is None:
            interrupted = signum

    previous_handlers = {
        signum: signal.signal(signum, interrupt)
        for signum in (signal.SIGINT, signal.SIGTERM)
    }
    try:
        log_file = log_path.open("x", encoding="utf-8", buffering=1)
        sudo = shutil.which("sudo")
        if not Path(TCPDUMP).is_file() or sudo is None:
            raise CaptureError("macOS tcpdump or sudo is unavailable")
        before = network_snapshot()
        require_default_coverage(before)
        log_lock = threading.Lock()
        captures = {name: Capture(name, sudo, log_file, log_lock) for name in before["interfaces"]}
        deadline = time.monotonic() + READY_TIMEOUT_SECONDS
        for capture in captures.values():
            if interrupted is not None:
                break
            capture.start()
        while interrupted is None:
            for name, capture in captures.items():
                if capture.errors or capture.process.poll() is not None:
                    raise CaptureError(f"tcpdump failed at startup on {name}")
            pending = [name for name, capture in captures.items() if not capture.ready.is_set()]
            if not pending:
                break
            if time.monotonic() >= deadline:
                raise CaptureError("timed out waiting for tcpdump on: " + ", ".join(pending))
            time.sleep(0.05)

        if interrupted is None:
            test_process = subprocess.Popen(command, cwd=ROOT, start_new_session=True)
            deadline = time.monotonic() + TEST_TIMEOUT_SECONDS
            while interrupted is None and test_process.poll() is None:
                if time.monotonic() >= deadline:
                    timed_out = True
                    break
                time.sleep(0.1)
            after = network_snapshot()
            require_default_coverage(after)
            if before["interfaces"] != after["interfaces"]:
                errors.append("UP IPv4/IPv6 interface set changed during the focused test")
            if before["default_route_interfaces"] != after["default_route_interfaces"]:
                errors.append("default-route interfaces changed during the focused test")
    except RUN_ERRORS as exc:
        errors.append(str(exc))
    finally:
        try:
            stop_process_group(test_process)
        except RUN_ERRORS as exc:
            errors.append(f"test cleanup failed: {exc}")
        for name, capture in captures.items():
            try:
                capture.request_stop()
            except RUN_ERRORS as exc:
                errors.append(f"could not stop capture on {name}: {exc}")
        for name, capture in captures.items():
            try:
                capture.finish()
            except RUN_ERRORS as exc:
                errors.append(f"capture cleanup failed on {name}: {exc}")
        if log_file is not None:
            try:
                log_file.close()
            except OSError as exc:
                errors.append(f"capture log close failed: {exc}")

    per_interface = {name: capture.result() for name, capture in captures.items()}
    ready = bool(per_interface) and all(item["ready"] for item in per_interface.values())
    control = any(item["control_dns_observed"] for item in per_interface.values())
    strict = any(item["strict_dns_observed"] for item in per_interface.values())
    test_exit_code = test_process.returncode if test_process is not None else None
    if interrupted is not None:
        errors.append(f"interrupted by signal {interrupted}")
    proof_passed = (
        test_exit_code == 0 and not timed_out and not errors and ready and control and not strict
        and all(not item["capture_errors"] for item in per_interface.values())
    )
    summary = {
        "started_at_utc": now.isoformat(),
        "network_before": before,
        "network_after": after,
        "capture_interfaces": per_interface,
        "capture_filter": FILTER,
        "capture_log": str(log_path.relative_to(ROOT)),
        "capture_ready": ready,
        "control_dns_observed": control,
        "strict_dns_observed": strict,
        "focused_test": FOCUSED_TEST,
        "xcodebuild_exit_code": test_exit_code,
        "timed_out": timed_out,
        "interrupted_signal": interrupted,
        "error": "; ".join(errors) or None,
        "proof_passed": proof_passed,
    }
    try:
        with summary_path.open("x", encoding="utf-8") as output:
            json.dump(summary, output, indent=2, sort_keys=True)
            output.write("\n")
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
    print(f"EPUB isolation diagnostics: {summary_path.relative_to(ROOT)}")

    if interrupted is not None:
        return 128 + interrupted
    if timed_out:
        return 124
    if test_exit_code not in (None, 0):
        return test_exit_code
    if not proof_passed:
        failures = errors + [
            f"{name}: {'; '.join(item['capture_errors'])}"
            for name, item in per_interface.items() if item["capture_errors"]
        ]
        if not control:
            failures.append("control DNS was not observed")
        if strict:
            failures.append("strict DNS was observed")
        print("EPUB isolation proof failed: " + "; ".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
