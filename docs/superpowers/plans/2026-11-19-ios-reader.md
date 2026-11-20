# BookReader iOS 15 Implementation Plan

**Source of requirements:** `docs/superpowers/specs/2026-11-19-ios-reader-design.md` (approved by user in conversation), with research in `.ai/RESEARCH/ios-reader/platform-and-build.md`.
**Goal and user:** Deliver a usable local iOS 15 reading app for PDF, EPUB without DRM, and TXT, with an intuitive library/reader flow and an unsigned arm64 IPA build from GitHub Actions.
**Non-goals:** TTS, OCR, DRM, cloud sync, accounts, downloads, annotations, format conversion, unsupported ebook formats, App Store signing/distribution.
**Acceptance mode:** Real-use for the supported reader path; device/iOS 15 and GitHub Actions remain evidence gates until actually exercised.
**Success scenario:** Import a Vietnamese EPUB from Files, open its table of contents, read and change typography, close/reopen offline, and resume at the saved location. Equivalent PDF/TXT flows must work.
**Failure scenario:** Corrupt, DRM/password-protected, malformed, oversized, or unsupported files are rejected with a useful error and do not create empty catalog entries or damage existing books.
**Integrated entrypoint:** Open app → Import book → choose file in Files → open from library → read.
**Authority:** User approved implementation. Allowed to create app source, Xcode project, package lock, tests, workflow, license notices, and implementation docs inside the current repository. No commit, push, remote creation, paid service, or destructive cleanup.
**Execution owner:** Main agent; one integration owner for shared project and CI boundaries.
**Continuation:** Current task todos; no separate STATE file is created because the existing journal is automatic and only intent/next changes belong there.

## Shared constraints and interfaces

- Deployment target iOS 15.0. Use Swift/SwiftUI APIs available on iOS 15, UIKit wrappers where required.
- Pin Readium Swift Toolkit 3.11.1 for EPUB. Resolve the actual dependency graph and preserve notices. Do not follow `develop`.
- Use PDFKit for PDF and a bounded native text reader for TXT. Do not make a generic reader abstraction that hides format-specific behavior.
- Use Core Data for catalog, last location, and bookmarks; FileManager/Application Support for imported files and staging; UserDefaults for small settings.
- Do not require a backend, account, telemetry, advertisement, or paid API.
- Import must copy to app-owned storage before catalog commit. Hash while copying. Enforce path and archive budgets before accepting EPUB. Do not modify the source file in Files.
- EPUB must use local resources only. Prove network blocking before production integration, including fixed-layout wrapper/iframe loads; if the chosen Readium hook cannot enforce it, stop and report the incompatibility instead of silently weakening the requirement.
- The app must expose real empty, progress, error, and no-search-results states. No dead TTS or unsupported-format buttons.
- CI must validate a simulator build/check and produce an arm64 device IPA artifact labeled unsigned. It must not claim App Store signing.

## Outcome 1: Project foundation and import/catalog boundary

**Acceptance:** The project opens with iOS 15 deployment target, builds its own app target, imports supported files into app-owned storage, persists catalog metadata, and rejects invalid/unsupported inputs without partial books.

**Targets and consumers:** Create the Xcode project, app target, Core Data model, import service, catalog store, format detection/preflight, fixture test target, and license notice path. The reader outcomes consume `BookRecord`, `ReadingLocation`, and imported file URLs through explicit repository interfaces.

**Interfaces:** `BookRecord` includes stable ID, relative storage path, format, title, author, file size, SHA-256, added/last-opened dates, progress, and optional cover cache path. Import returns per-file success/failure results; it never returns a catalog record until staging copy, hash, format validation, and minimal metadata extraction succeed.

**Internal steps:**
1. Create a shared Xcode project/scheme and iOS 15 app target with SwiftUI entrypoint, Core Data model, unit test target, and no external package except the pinned Readium package required by the EPUB outcome.
2. Add import staging and Application Support paths with UUID-based destinations. Implement streaming copy/hash, duplicate-byte detection, filename fallback metadata, and bounded failure categories.
3. Implement supported format detection and preflight fixtures: malformed EPUB, wrong extension, empty file, password PDF, unsupported extension, UTF-8/UTF-16 TXT, oversized/archive traversal fixtures. Keep fixture content synthetic and distributable.
4. Persist catalog and recover only the current interrupted import. Add focused tests for duplicate identity, partial import rollback, unsupported/error classification, and path confinement.
5. Add library empty/loading/error/no-results UI and real Files importer; wire book deletion to app-owned storage only.

**Evidence:** Focused Swift tests for catalog/import invariants; a simulator smoke path importing synthetic fixtures; structural check that the target and Core Data model exist. Real iOS 15 device remains separate evidence.

**Review:** Self-review plus security-focused review of import/path/archive handling before reader integration.

**Open decisions/stop conditions:** If Readium’s archive preflight or resource isolation cannot satisfy the agreed boundaries, stop the EPUB path and report the exact missing hook; do not replace it with an unreviewed custom engine.

## Outcome 2: PDF and TXT readers

**Acceptance:** From the library, a PDF opens with scroll/zoom/page navigation and text search where a text layer exists; a scan remains viewable without fake search. TXT opens with supported Unicode decoding, bounded rendering, text search, typography settings, bookmarks, and restore location after restart.

**Targets and consumers:** PDF reader view/controller wrapper, TXT reader model/view, shared reading-state store, bookmarks UI, settings/theme model.

**Interfaces:** PDF location stores page index plus available anchor; TXT location stores normalized offset/version. Both readers use the shared reading-state store but keep format-specific location encoding.

**Internal steps:**
1. Write focused tests for PDF location serialization and TXT decoding/normalization/long-line handling before implementation.
2. Implement PDFKit wrapper and search/page controls without claiming OCR or reflow.
3. Implement lazy/bounded TXT chunking, UTF-8/UTF-8 BOM/UTF-16 BOM decoding, search cancellation, typography settings, bookmark creation, and restore.
4. Integrate common reader chrome, dark/light handling, Dynamic Type/accessibility labels, and empty/error states.
5. Exercise PDF text/scan/password and TXT valid/invalid fixtures in simulator smoke checks.

**Evidence:** Focused unit tests plus simulator entrypoint smoke for representative PDF/TXT fixtures. Record any Apple runtime-specific gap as unverified rather than substituting source checks.

## Outcome 3: EPUB reader with offline/resource isolation

**Acceptance:** EPUB 2/3 non-DRM local books open through Readium 3.11.1, support reflow/fixed layout as available, table of contents, typography for reflow, search where supported, bookmarks, and Locator restore. Broken/DRM/unsupported books fail without catalog damage. Content cannot fetch external HTTP(S) resources when network is enabled.

**Targets and consumers:** Readium package products, EPUB reader wrapper, publication opener, locator adapter, search/TOC/bookmark UI, network isolation configuration, EPUB security fixtures.

**Interfaces:** `EPUBReader` receives a validated local book URL and serialized locator; emits locator changes and navigation/search results through the shared reading-state store. It must not own catalog persistence or import file mutation.

**Internal steps:**
1. Resolve Readium 3.11.1 and inspect the actual graph/licenses. Write a focused opening/locator contract fixture against local EPUBs before wiring UI.
2. Implement local publication opening and SwiftUI/UIKit bridge using the pinned documented APIs. Use the 3.11+ scheme-handler path; do not add legacy HTTP server dependencies.
3. Implement TOC, typography, search, bookmarks, and location persistence for reflow/fixed-layout behavior exposed by the navigator.
4. Implement and prove pre-first-load network isolation for reflow and fixed-layout wrapper/iframe/subresources, including the native loader path. If no safe hook covers all paths, preserve the failing evidence and stop this outcome for decision.
5. Exercise malformed, DRM, remote-resource, image-only, and Vietnamese EPUB fixtures; integrate errors into library UI.

**Evidence:** Focused local publication tests, network-request probe fixture, simulator reader smoke, dependency/license manifest. No claim of offline security from airplane mode alone.

## Outcome 4: GitHub Actions build and packaging

**Acceptance:** A real workflow builds/checks the app and uploads `BookReader-ios15-unsigned.ipa`; structural checks confirm arm64 device target, iOS 15 minimum, required resources, and failure on build/check errors.

**Targets and consumers:** `.github/workflows/ios.yml`, shared Xcode scheme/project, package resolution, CI validation script, third-party notices.

**Internal steps:**
1. Add workflow dispatch and relevant push/PR triggers, least-privilege read-only permissions, concurrency cancellation, pinned action revisions, and SPM cache keyed by lockfile/toolchain.
2. Validate available macOS/Xcode toolchain at job start, then build/test on an available simulator and build `generic/platform=iOS` with deployment target 15.0 and arm64 without App Store signing.
3. Create `Payload/BookReader.app`, zip as an explicitly unsigned IPA, compute SHA-256, and validate executable architecture, `MinimumOSVersion`, bundle resources, and test results before upload.
4. Keep artifact retention short and omit DerivedData/books. Ensure any failure prevents success artifact publication.
5. Run the workflow in the user’s repository when a remote exists; otherwise validate the workflow syntax and local script only, recording the missing remote execution evidence.

**Evidence:** Workflow run URL/log/artifact for integrated CI; local structural validation output where CI is not yet executable. This does not prove installation on the user’s jailbreak setup.

## Outcome 5: Integrated reader smoke, docs, and handoff

**Acceptance:** The real app flow is reachable from launch through import/library/reader for all supported formats, failure states are understandable, and all named evidence gaps are explicit.

**Targets and consumers:** app navigation, README/build instructions, license notices, fixture documentation, acceptance checklist.

**Internal steps:**
1. Run focused tests and the simulator smoke path after all outcomes land; do not reuse stale pre-integration evidence.
2. Run a manual/automated simulator flow covering A2-A11 as far as the host runtime supports, including no-network fixture observation.
3. Run CI packaging checks and inspect the actual artifact. Do not claim real iOS 15 device success without user device evidence.
4. Update README with exact local/Actions commands, unsupported formats, unsigned IPA status, and TTS future scope. Preserve third-party notices.
5. Self-review changed callers, paths, security boundaries, resource handling, and documentation. Obtain independent audit of the completed implementation before any commit or release claim.

**Evidence:** Focused tests, simulator smoke output, CI artifact evidence, and an explicit list of unverified physical-device/TTS boundaries.

## Review focus

- Actual Readium 3.11.1 API and package graph, not remembered signatures.
- EPUB local-resource and request isolation across reflow/fixed-layout and first load.
- Archive traversal/bomb and staging/catalog recovery behavior.
- Core Data/file consistency after cancellation, crash, deletion, and duplicate import.
- iOS 15 API availability and accessibility under large text/rotation/VoiceOver.
- IPA packaging correctness versus signed/App Store assumptions.
- No dead controls, fabricated metadata, secrets, books, or private content in logs/artifacts.
## Verified implementation dependency

- `ZIPFoundation` is required by the archive preflight in `BookReader/Services/EPUBArchivePreflight.swift`. Resolve its current package release and API before project integration; pin a stable version in Swift Package Manager and commit the generated `Package.resolved`. It must not silently skip entry checks or inflate resource limits.
