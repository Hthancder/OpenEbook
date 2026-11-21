# Readium source-preparation integrity audit

**PASS for the corrected source-preparation boundary.** This is a working-tree source verdict, not an audit of a staged commit and not acceptance of hosted resolution, compilation, or EPUB runtime isolation. The earlier source FAIL is superseded for the corrected fingerprint below.

## Scope and inspected snapshot

Audited `Scripts/prepare-readium.sh`, `Scripts/generate-project.sh`, all four files under `Scripts/Patches/`, the local Readium pin in `project.yml`, both Readium notices, the app-side LF policy in `.gitattributes`, and source-gate evidence in `build/evidence/epub-source-gate.json`. The Swift runtime test, workflow, and wrapper were excluded. The app base was `4d933d65abca209393ad630c862792b9eaeb2a3f`; the index had no staged entries. The current script, patch and manifest exactly matched the corresponding saved `build/readium-gate-final` probe inputs and their hashes in the evidence JSON.

| File | SHA-256 |
| --- | --- |
| `Scripts/prepare-readium.sh` | `26f21b445497f7bdbfd777ab094eea0ca854948f458e9024b1f66b89b07d7cdc` |
| `Scripts/generate-project.sh` | `5296a5a9eec30470c593170d562a98d767b6d7fd04b51b689834ab192124cb55` |
| `Scripts/Patches/readium-3.11.1-offline.patch` | `5d6b65943a9e8cc4d4503ee47d1ba712acdf6bacd5d8886e448c970d7bb71d98` |
| `Scripts/Patches/readium-3.11.1-offline.sha256` | `54037c351b7e8a8e180930beabd687fa069063328f5479eb4e1ab3a1bdbaa0e2` |
| `.gitattributes` | `41e90cdc6ca567041134d66842c7cfc9a964bf2b97bf615f77addd1b17435223` |
| `build/evidence/epub-source-gate.json` | `b3470103954f6f38898b7b863af2628f98260272b5e0c0c3acc4c5edeb07599b` |

## Acceptance findings

### Pin, clone policy, and package selection: PASS

- The [upstream 3.11.1 tag lookup](https://api.github.com/repos/readium/swift-toolkit/commits/3.11.1) returned HTTP 200 and `9a8c094b72245fd27043c9d298005e5c78b32a01`. The [commit ZIP](https://codeload.github.com/readium/swift-toolkit/zip/9a8c094b72245fd27043c9d298005e5c78b32a01) streamed to SHA-256 `105975c9fe5a2cc333d910c493a0b6bd8f660374b9b87d486b6794e7831793c0`, which matches `Scripts/Patches/README.md`.
- `Scripts/prepare-readium.sh:11-15` sets `core.autocrlf=false` at clone time and requires exact `HEAD`. The corrected probe independently reported the expected `HEAD` and local `core.autocrlf=false`. Earlier CRLF checkouts passed reverse applicability but failed all four raw-byte file hashes; LF normalization recovered all four matches. Rejecting those existing checkouts is expected. No checkout was rewritten by this audit.
- `.gitattributes:1-4` pins LF for script inputs and the patch/manifest. `git check-attr text eol` returned `text: set`, `eol: lf` for both shell scripts, the patch, and the manifest. `git cat-file --filters` on the tracked generator returned zero CR bytes with the corrected policy, versus six CRLF lines in the prior snapshot. The previous in-memory CRLF patch failed the same clean-index check that passed with LF bytes. The app-side portability finding is closed.
- `project.yml:8-10` selects `build/Readium`. `Scripts/generate-project.sh:6-7` runs the source gate before XcodeGen. Project generation itself was not run during the audit.

### Exact patch surface and full bytes: PASS

`git apply --numstat` listed exactly the following four paths, with added/deleted line counts of 11/1, 5/1, 15/0 and 21/6 respectively. `git apply --summary` emitted no mode, create/delete or rename changes. On the corrected probe, `git apply --cached --check` against the pinned index and `git apply --reverse --check` against the patched worktree both returned 0. An independent raw-file SHA-256 check confirmed all full-file digests below, relative to `Sources/Navigator/EPUB/`:

```text
6dcb7d3f4aeed20243a7029143c0553d1c0598d477d80d9f031632ae72859880  EPUBNavigatorViewController.swift
d483323b9d04f3598074ab359099571e443b56c52cbd13dbb8fb3f9ce780470f  EPUBNavigatorViewModel.swift
6372d70fd711262c2e219f022b08806a064a11de41d887acc8c81cf3107b69e8  EPUBSpreadView.swift
32b7ac3be0d60171bd526bb6d33382cad3a3a53f86c9c8c3e2b15c5fb9c13479  WebViewServer.swift
```

### Clean-source guards: PASS for the bounded source review

- `Scripts/prepare-readium.sh:16-18` now checks the index and all untracked entries before the patch branches. The standalone `UNTRACKED=` assignment preserves Git failure under `set -e`. The correlated evidence records exit 128 for an invalid Git working directory, replacing the prior predicate's independently observed false success. The early checks close the prior dirty-input-before-apply finding.
- `git diff --quiet --cached` returned 0 on the corrected LF probe. The unrelated tracked check returned 0 with the four exact exclusions; in the prior LF probe, dropping one exclusion yielded 1, detecting that changed tracked file. The forward branch also checks the unstaged tracked diff before writing. No staged or ordinary-untracked edit was created to exercise a full negative run; those cases were reviewed by control flow and the corresponding Git predicates.
- The corrected probe has the ignored challenge at `Sources/Navigator/EPUB/.build/Injected.swift`. `git check-ignore -q` returned 0 and plain `git ls-files --others` listed it. Earlier differential probing showed `--exclude-standard` hides it; the corrected script does not use that flag or a path exception. The evidence records corrected clean preparation exit 0 and ignored-source rejection exit 1. The audit used read-only Git operations; it did not apply a patch or create a challenge file.

### Repeat after resolution: supported boundary accepted; hosted proof UNVERIFIED

`Scripts/Patches/README.md:29` defines resolution from the generated app project, with scratch space, lockfiles, and configuration kept outside `build/Readium`. Strict untracked rejection remains appropriate at that boundary. Package-root CLI resolution inside Readium is outside the supported path: SwiftPM [defaults](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2.4-RELEASE/Sources/Workspace/Workspace%2BConfiguration.swift#L214-L230) put `.build`, `Package.resolved`, and local configuration beneath the package root. Readium ignores those paths, but the gate would reject any untracked contents. The existing tracked `.swiftpm/xcode` file does not demonstrate resolver output. No exemption of all ignored files, `.build` at any depth, or the whole `.swiftpm` tree is justified.

The evidence JSON records an already-patched success on the earlier LF gate, not a post-resolution repeat. The corrected probe confirms that reverse applicability, index, outside-patch diff, and exact hashes all pass on already-patched content; the retained challenge correctly prevents a clean end-to-end repeat on that snapshot. **Integrated proof still needed:** resolve the app project on macOS and rerun the actual preparation gate immediately afterward. The workflow/wrapper were excluded, and no hosted result was audited. If the supported resolver leaves files inside `build/Readium`, the strict gate should fail and the integration must keep that state outside the checkout rather than permit ignored source.

### Original license and notices: PASS for source and notice bytes

The [pinned upstream LICENSE](https://raw.githubusercontent.com/readium/swift-toolkit/9a8c094b72245fd27043c9d298005e5c78b32a01/LICENSE), the pinned Git blob, the original LF checkout license, `Scripts/Patches/Readium-LICENSE.txt`, and the full BSD block at `BookReader/Resources/ThirdPartyNotices.md:17` matched exactly (1,507 bytes; SHA-256 `f47741fce46e526840d3d5b70788a3d791144411dd21c94a73864188770e2d82`). The original in the existing CRLF `build/Readium` matched after newline normalization only. The script's nonempty check is not a byte comparison; equality above is independently checked. The repository notice references both copies, and `project.yml:27` includes `BookReader/Resources`. IPA resource inspection and transitive license clearance are outside this result.

## Handoff

No remaining confirmed blocker in the corrected source-preparation snapshot. The index was empty, so no staged-commit secret verdict is implied. The earlier scoped pattern scan reported no matches; it does not cover a future staged set. No build, lint, test, formatter, resolver, Git mutation, or source edit was performed by this audit. Final project resolution, compilation, and hosted EPUB no-egress acceptance are UNVERIFIED; keep EPUB import and reader locked until the separate runtime gate passes.
