# Approved EPUB first-load isolation

Outcome: finish the existing offline EPUB reader without weakening its fail-closed gate. Approval in this conversation permits a minimal pinned Readium source patch; no new package or unpinned fork. Existing PDF/TXT IPA and evidence remain unchanged until replacement succeeds.

## Authority and acceptance

- Readium 3.11.1 commit `9a8c094b72245fd27043c9d298005e5c78b32a01`; retain upstream BSD-3-Clause license and reviewable patch in repository.
- Source trace shows initial reflowable/fixed WebKit load starts before `setupUserScripts`. Rules must be in `WKWebViewConfiguration` before constructing every web view, not added later.
- Native HTTP requests must fail with a real error; local archive reads remain real.
- Restricted custom-scheme resource responses carry restrictive CSP (including standalone SVG), and automatic external navigations are rejected. Author scripts, workers, frames outside packaged content and network connections are not permitted. Readium's own injected reading-system scripts must still work.
- A hostile EPUB must render local content while a local observer sees zero publication-origin network requests. A positive control must prove the observer and ordinary WebKit requests work. Cover first load, later chapter, view recreation, remote CSS/image/font/script/frame, script/network attempts and automatic navigation.
- Retain existing EPUB import refusal until source patch compiles and the real navigator isolation test passes. Then test actual EPUB import, TOC, preferences, search, bookmarks and reopen before building replacement unsigned IPA.

## Implementation sequence

1. Stage exact upstream source in ignored build directory; prepare narrow patch exposing an optional precompiled offline rule list. Apply list before web-view creation; restricted navigation and response CSP share that policy. Fail preparation if upstream commit/context differs. Preserve license and source identity.
2. Integrate local patched package into existing XcodeGen generation path. Native offline HTTP client and EPUB model select strict policy. Add meaningful navigator/runtime isolation fixtures and observer, no app import unlock yet.
3. Run independent security review and actual hosted isolation probe. Fix only evidenced defects. Once positive and zero-egress controls pass, unlock existing import/reader paths and exercise existing EPUB feature acceptance.
4. Build unsigned device IPA, verify bytes/checksum/architecture/minimum OS and release fixture exclusion. Report physical iOS 15 and other unexercised limits honestly.

No duplicate runs solely to reconfirm known failures. Tests run after changed behavior or new evidence instrumentation. No feature expansion, permanent fake readers, silently narrowed EPUB policy, or security bypasses.
