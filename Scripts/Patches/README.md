# Readium 3.11.1 offline navigator patch

## Upstream identity and license

- Upstream: `readium/swift-toolkit`, tag `3.11.1`.
- Required commit: `9a8c094b72245fd27043c9d298005e5c78b32a01`.
- Source archive: `https://codeload.github.com/readium/swift-toolkit/zip/9a8c094b72245fd27043c9d298005e5c78b32a01`.
- Archive SHA-256 captured for patch generation: `105975c9fe5a2cc333d910c493a0b6bd8f660374b9b87d486b6794e7831793c0`.
- License: upstream BSD 3-Clause. `Readium-LICENSE.txt` reproduces the full upstream `LICENSE` without modification. Retain the upstream source notices and license in redistributed source, and reproduce its terms in the documentation or other materials accompanying binary distributions. The license copy supplements, rather than replaces, upstream `LICENSE`.

`readium-3.11.1-offline.patch` is a five-line-context unified diff generated against that exact archive. It changes only these upstream-relative paths:

- `Sources/Navigator/EPUB/EPUBNavigatorViewController.swift`
- `Sources/Navigator/EPUB/EPUBNavigatorViewModel.swift`
- `Sources/Navigator/EPUB/EPUBSpreadView.swift`
- `Sources/Navigator/EPUB/WebViewServer.swift`

`readium-3.11.1-offline.sha256` pins the complete post-patch bytes of those four files. It is not a manifest of the entire toolkit. Unrelated upstream files, dependencies and the original license must remain intact.

## Apply order

1. Obtain a clean upstream checkout at the required commit. Confirm `git rev-parse HEAD` equals the full commit above and there are no pre-existing source edits. Do not apply to another tag, a floating branch, or an already modified tree.
2. Before dependency resolution or compilation, run `git apply --check` on this patch from the upstream root, then `git apply` on the same file. The patch paths use `a/` and `b/` prefixes compatible with Git's default strip level. Do not use fuzz or ignore whitespace failures.
3. From the patched upstream root, run `shasum -a 256 -c /absolute/path/to/Scripts/Patches/readium-3.11.1-offline.sha256`. All four hashes must match. `git apply --reverse --check` can identify an already-applied patch, but it does not replace the complete-file hash check.
4. Resolve and build the application against this patched local toolkit, not the unpatched remote package. Retain upstream `LICENSE` and this directory's license copy, and include the required notice with distributed binaries.

The repository's `Scripts/prepare-readium.sh` owns automated preparation, called by `Scripts/generate-project.sh` before XcodeGen. A fresh clone records `core.autocrlf=false` so full-file hashes remain byte-exact on Windows and macOS. Preparation rejects staged edits, unrelated tracked edits and all additional untracked files, including ignored files; the four patched files must match the manifest exactly. An existing checkout with converted line endings fails rather than being silently rewritten. This preparation does not unlock EPUB import or reading.

Resolve dependencies from the generated application project, not by running SwiftPM inside `build/Readium`. Keep its resolver scratch space, lockfiles and configuration outside the prepared source checkout. The workflow reruns preparation immediately after the application's package resolution; any generated or changed source-checkout file fails before compilation. No `.swiftpm` configuration or ignored-source exception is allowed.

## Public API and activation

The patch adds one public optional property and a trailing defaulted initializer argument:

```swift
EPUBNavigatorViewController.Configuration.offlineContentRuleList: WKContentRuleList?

EPUBNavigatorViewController.Configuration(
    // Existing arguments remain unchanged.
    offlineContentRuleList: precompiledRules
)
```

The property and argument default to `nil`, preserving the original navigator behavior. The application must successfully compile strict WebKit content-blocking rules before constructing the navigator, then provide the resulting list. A non-nil list activates all three patch controls together; there are no independent policy switches. The patch cannot determine whether a caller-supplied rule list actually blocks network requests. Compilation failure or a missing strict list must remain a fail-closed application condition.

1. Every spread installs the supplied list on `WKWebViewConfiguration.userContentController` before creating `WebView`, invoking `setupWebView`, or submitting a load. Fixed-layout, reflowable, preloaded and recreated spreads share this initializer.
2. Publication resource responses receive one restrictive CSP header before `didReceive(data)`, for both full responses and byte ranges, regardless of media type. This includes standalone SVG. Publication routes use the callback-resource branch of `WebViewServer`; trusted static file/directory asset routes do not receive this CSP. The bundled fixed-layout wrapper remains unchanged: its trusted markup loads the local Readium wrapper script, and the publication iframes receive their own response policy. No author-script exception is added.
3. Navigation in an existing frame permits only the server's exact `readium` scheme or exact `about:blank` wrapper URL. Other automatic schemes, missing URLs and nil target frames are cancelled. Activated links still use the existing internal/external delegate callbacks and remain cancelled in WebKit; the application must refuse external URLs unless it later implements a deliberate user-confirmed prompt. This patch does not open external URLs or create popup web views.

The single publication-response policy is:

```text
default-src 'none'; connect-src 'none'; script-src 'none'; style-src readium: 'unsafe-inline'; img-src readium: data:; font-src readium:; media-src readium:; frame-src readium:; child-src readium:; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'
```

The scheme allowlist is not a native networking policy or a full URL-origin validator. Unregistered `readium` URLs continue to fail through the existing custom-scheme server. Remote publications with an HTTP base URL are not an offline mode supported by this patch. CSS/font/image/media references must resolve to packaged resources to render.

## Runtime limits and release gate

This source patch is not evidence of zero network egress. No native build, simulator run, hostile EPUB probe, or application test suite was run while producing it. Parent integration owns compile checks, patch applicability/hash checks and native runtime acceptance.

Still unverified on the target WebKit runtime:

- Enforcement of CSP delivered with custom-scheme `HTTPURLResponse`, including standalone SVG and fixed-layout publication frames.
- Whether Readium's injected `WKUserScript` and native JavaScript evaluation keep working with `script-src 'none'`; do not relax author-script policy to hide a rendering failure.
- First-load, preload and recreated-view request blocking, including WS/WSS and nested contexts. Content rules and navigation delegates are layered controls, not a substitute for an observed hostile-publication test.
- Nil-target popup and automatic navigation behavior, including redirects and non-HTTP schemes.

Keep `ImportService` and `ReaderHost` EPUB refusal locks in place until an actual navigator safety probe passes. A positive control must first prove that the observer sees ordinary WebKit requests. The hostile EPUB must render packaged content with zero observed publication-origin requests at first load, later chapters and view recreation. Cover remote CSS, images, fonts, scripts, frames, script-driven connections and automatic navigation. Keep native HTTP requests fail-closed separately, then verify real import, TOC, preferences, search, bookmarks and reopen before releasing a replacement IPA. No app unlock is included here.
