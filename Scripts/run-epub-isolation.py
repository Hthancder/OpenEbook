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
FILTER = "port 53 or udp port 5353"
LISTENING = re.compile(r"\blistening on pktap(?:,all)?\b", re.IGNORECASE)
KERNEL_DROPS = re.compile(r"^(\d+) packets dropped by kernel$", re.IGNORECASE)
MARKER = re.compile(
    r"\b(bookreader-(control|strict)-[0-9a-f-]+\.example\.com)\b", re.IGNORECASE
)
FOCUSED_TEST = "-only-testing:BookReaderTests/EPUBIsolationTests"


class CaptureError(RuntimeError):
    pass


class InterruptedRun(Exception):
    def __init__(self, signum):
        self.signum = signum


class Capture:
    def __init__(self, log_file):
        self.log_file = log_file
        self.log_lock = threading.Lock()
        self.state_lock = threading.Lock()
        self.ready = threading.Event()
        self.process = None
        self.readers = []
        self.exit_code = None
        self.early_exit = False
        self.control_seen = False
        self.strict_seen = False
        self.kernel_drops = None
        self.stderr_tail = []
        self.reader_error = None

    def start(self):
        tcpdump = "/usr/sbin/tcpdump"
        sudo = shutil.which("sudo")
        if not Path(tcpdump).is_file() or sudo is None:
            raise CaptureError("macOS tcpdump or sudo is unavailable")

        self.process = subprocess.Popen(
            [sudo, "-n", tcpdump, "-i", "pktap,all", "-l", "-n", "-s", "0", "-vvv", FILTER],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            start_new_session=True,
        )
        self.readers = [
            threading.Thread(target=self._read_stream, args=(self.process.stdout, False), daemon=True),
            threading.Thread(target=self._read_stream, args=(self.process.stderr, True), daemon=True),
        ]
        for reader in self.readers:
            reader.start()

        deadline = time.monotonic() + READY_TIMEOUT_SECONDS
        while not self.ready.wait(0.1):
            if self.process.poll() is not None:
                self._join_readers()
                raise self._capture_failure(
                    f"tcpdump exited before pktap,all became ready (exit {self.process.returncode})"
                )
            if time.monotonic() >= deadline:
                self.stop()
                raise CaptureError("timed out waiting for tcpdump pktap,all readiness")

    def _read_stream(self, stream, is_stderr):
        try:
            for line in stream:
                with self.log_lock:
                    self.log_file.write(line)
                    self.log_file.flush()
                if is_stderr:
                    stripped = line.strip()
                    self.stderr_tail.append(stripped)
                    del self.stderr_tail[:-20]
                    drops = KERNEL_DROPS.fullmatch(stripped)
                    if drops:
                        self.kernel_drops = int(drops.group(1))
                    if LISTENING.search(line):
                        self.ready.set()
                else:
                    for _hostname, kind in MARKER.findall(line):
                        with self.state_lock:
                            if kind.lower() == "control":
                                self.control_seen = True
                            elif kind.lower() == "strict":
                                self.strict_seen = True
        except (OSError, ValueError) as exc:
            self.reader_error = f"capture output reader failed: {exc}"

    def _capture_failure(self, detail):
        diagnostic = "; ".join(self.stderr_tail)
        return CaptureError(f"{detail}: {diagnostic}" if diagnostic else detail)

    def _signal_group(self, signum):
        if self.process is None:
            return
        try:
            os.killpg(self.process.pid, signum)
        except ProcessLookupError:
            pass
        except PermissionError:
            sudo = shutil.which("sudo")
            if sudo is None:
                raise CaptureError("cannot signal the owned privileged capture group")
            result = subprocess.run(
                [sudo, "-n", "/bin/kill", "-s", signal.Signals(signum).name[3:], "--", f"-{self.process.pid}"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=CHILD_SHUTDOWN_SECONDS,
            )
            if result.returncode != 0 and self.process.poll() is None:
                raise CaptureError("privileged capture group did not accept the shutdown signal")

    def _join_readers(self):
        for reader in self.readers:
            reader.join(timeout=2)
        if any(reader.is_alive() for reader in self.readers):
            self.reader_error = "capture output did not reach EOF"
            raise CaptureError(self.reader_error)

    def stop(self):
        if self.process is None:
            return
        if self.process.poll() is None:
            self._signal_group(signal.SIGINT)
            try:
                self.exit_code = self.process.wait(timeout=CHILD_SHUTDOWN_SECONDS)
            except subprocess.TimeoutExpired:
                self._signal_group(signal.SIGTERM)
                try:
                    self.exit_code = self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self._signal_group(signal.SIGKILL)
                    self.exit_code = self.process.wait()
        else:
            self.exit_code = self.process.returncode
        self._join_readers()

    def result(self):
        with self.state_lock:
            return {
                "control_dns_observed": self.control_seen,
                "strict_dns_observed": self.strict_seen,
                "capture_exit_code": self.exit_code,
                "capture_exited_early": self.early_exit,
                "capture_error": self.reader_error,
                "kernel_dropped_packets": self.kernel_drops,
            }


def stop_process_group(process, grace_seconds=CHILD_SHUTDOWN_SECONDS):
    if process is None or process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=grace_seconds)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


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
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}"
    log_path = diagnostics / f"epub-isolation-tcpdump-{run_id}.log"
    summary_path = diagnostics / f"epub-isolation-{run_id}.json"
    started_at = datetime.now(timezone.utc).isoformat()
    capture = None
    test_process = None
    test_exit_code = None
    timed_out = False
    interrupted = None
    error = None
    proof_passed = False

    def interrupt(signum, _frame):
        raise InterruptedRun(signum)

    previous_handlers = {
        signum: signal.signal(signum, interrupt)
        for signum in (signal.SIGINT, signal.SIGTERM)
    }
    try:
        with log_path.open("x", encoding="utf-8", buffering=1) as log_file:
            capture = Capture(log_file)
            capture.start()
            test_process = subprocess.Popen(command, cwd=ROOT, start_new_session=True)
            try:
                test_exit_code = test_process.wait(timeout=TEST_TIMEOUT_SECONDS)
            except subprocess.TimeoutExpired:
                timed_out = True
                stop_process_group(test_process)
                test_exit_code = test_process.returncode
            if capture.process.poll() is not None:
                capture.early_exit = True
            capture.stop()
            result = capture.result()
            proof_passed = (
                not timed_out
                and test_exit_code == 0
                and result["capture_exit_code"] == 0
                and not result["capture_exited_early"]
                and result["capture_error"] is None
                and result["kernel_dropped_packets"] == 0
                and result["control_dns_observed"]
                and not result["strict_dns_observed"]
            )
    except InterruptedRun as exc:
        interrupted = exc.signum
        error = f"interrupted by signal {interrupted}"
    except (CaptureError, OSError, subprocess.SubprocessError) as exc:
        error = str(exc)
    finally:
        for signum in previous_handlers:
            signal.signal(signum, signal.SIG_IGN)
        try:
            stop_process_group(test_process)
        except (CaptureError, OSError, subprocess.SubprocessError) as exc:
            error = error or f"test cleanup failed: {exc}"
        try:
            if capture is not None:
                capture.stop()
        except (CaptureError, OSError, subprocess.SubprocessError) as exc:
            error = error or f"capture cleanup failed: {exc}"
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        if error is not None:
            proof_passed = False

    result = capture.result() if capture is not None else {
        "control_dns_observed": False,
        "strict_dns_observed": False,
        "capture_exit_code": None,
        "capture_exited_early": False,
        "capture_error": None,
        "kernel_dropped_packets": None,
    }
    summary = {
        "started_at_utc": started_at,
        "capture_interface": "pktap,all",
        "capture_filter": FILTER,
        "capture_ready": bool(capture and capture.ready.is_set()),
        "capture_log": str(log_path.relative_to(ROOT)),
        "focused_test": FOCUSED_TEST,
        "xcodebuild_exit_code": test_exit_code,
        "timed_out": timed_out,
        "interrupted_signal": interrupted,
        "error": error,
        **result,
        "proof_passed": proof_passed,
    }
    with summary_path.open("x", encoding="utf-8") as output:
        json.dump(summary, output, indent=2, sort_keys=True)
        output.write("\n")
    print(f"EPUB isolation diagnostics: {summary_path.relative_to(ROOT)}")

    if interrupted is not None:
        return 128 + interrupted
    if timed_out:
        return 124
    if test_exit_code not in (None, 0):
        return test_exit_code
    if error is not None or not proof_passed:
        if error:
            print(f"EPUB isolation capture failed: {error}", file=sys.stderr)
        elif result["capture_error"]:
            print(f"EPUB isolation capture failed: {result['capture_error']}", file=sys.stderr)
        elif result["kernel_dropped_packets"] is None:
            print("EPUB isolation capture failed: tcpdump drop count was unavailable", file=sys.stderr)
        elif result["kernel_dropped_packets"]:
            print("EPUB isolation capture failed: tcpdump dropped packets in the kernel", file=sys.stderr)
        elif not result["control_dns_observed"]:
            print("EPUB isolation proof failed: control DNS was not observed", file=sys.stderr)
        elif result["strict_dns_observed"]:
            print("EPUB isolation proof failed: strict DNS was observed", file=sys.stderr)
        else:
            print("EPUB isolation proof failed: capture or focused test did not complete cleanly", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
