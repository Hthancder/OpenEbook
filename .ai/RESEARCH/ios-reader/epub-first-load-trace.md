# Readium 3.11.1 EPUB first-load trace

## Answer first

**No. `EPUBNavigatorDelegate.navigator(_:setupUserScripts:)` is not called before the first `WKWebView` load in Readium Swift Toolkit 3.11.1.** The controller's spread factory constructs the spread first and calls the delegate afterward. The spread initializer submits a load before returning. This applies to the first visible spread and to later newly constructed/preloaded spreads.

- **Reflowable EPUB:** `EPUBSpreadView.init` calls `loadSpread()` synchronously at line 104. Its override calls `webView.load(URLRequest(...))` at `EPUBReflowableSpreadView.swift:87`. Only after that initializer returns does `EPUBNavigatorViewController.swift:1265` call `setupUserScripts`. There is no intervening `Task` that postpones this load call until after the callback. [S1][S2][S3]
- **Fixed-layout EPUB:** the order is earlier still: the base initializer calls the fixed-layout `setupWebView()` override at line 94; that override calls `loadHTMLString` for Readium's bundled wrapper at `EPUBFixedSpreadView.swift:61`. The publisher content subsequently loads in iframes after wrapper completion. The trusted wrapper is not itself evidence of a remote leak, but the callback is still after the first WebKit load. [S2][S4][S5]
- **Setting the controller delegate after controller construction but before `viewDidLoad` is sufficient to receive the callback, but insufficient to make it a pre-load policy hook.** Controller construction does not itself create/load the first spread. That work begins from `viewDidLoad` through an asynchronous `initialize()`. Once spread construction starts, its initializer's load submission precedes the delegate callback. [S1][S6][S7]

**Runtime status: UNVERIFIED.** Source proves the order of the API calls, not that a packet actually leaves before the late rule is installed. WebKit can process a submitted navigation asynchronously. Neither that fact nor execution on the main actor establishes a documented guarantee that adding a content rule list afterward will protect every request belonging to the already-submitted navigation. This report must not be read as an observed leak or a runtime no-network pass.

**Recommendation:** retain the existing EPUB import/reader locks. The current public callback cannot establish the required strict pre-first-load rule installation. Native HTTP rejection has a small public-API route, but it does not protect WebKit. The missing prerequisite for that strict WebKit route is an approved, pinned change exposing/applying policy before *both* the reflowable document load and fixed-layout wrapper load, preferably before constructing the `WKWebView`. An application-level resource transformation is publicly possible, but is a different protection design with behavior/coverage consequences, not evidence that the existing callback is safe. See the bounded recommendation below.

## Scope, pin and method

- Source version: official `readium/swift-toolkit` **3.11.1**, commit **`9a8c094b72245fd27043c9d298005e5c78b32a01`**. All source links below use this immutable commit, not `main` or a newer release. The official tag tree returned this SHA with `truncated=false`. The downloaded app build's `build/artifacts/run-44822095576/BookReader.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:68-73` records the same version and revision. [PIN]
- Discovery used the official recursive source-tree listing before opening spread, wrapper, resource and toolkit implementation files. [PIN]
- The codebase-memory project lookup and symbol query were attempted first. This checkout is not indexed; the query returned `project not found or not indexed`. No indexing/install/change was performed. Targeted local reads and pinned official source replaced graph evidence.
- Context7 was queried against `/readium/swift-toolkit/3.11.1`. It located the versioned opening-publications guide and the fixed-layout wrapper description, but did not establish hook ordering. The implementation below is the evidence for that ordering. [GUIDE][CONTRIBUTING]
- Local app source was read, not changed. No build, test, simulator/device run, dependency install, commit, push or shipping-policy change was performed. This is source-level investigation plus a proposed future observation protocol.
- The historical research file was not treated as authority for call ordering and was not overwritten. This report is a separate, newly created artifact.

## Exact controller-to-first-spread chain

| Order | Pinned source | Behavior and implication |
| --- | --- | --- |
| 1 | `EPUBNavigatorViewController.swift:278-307` [S6] | Public convenience initializer checks restrictions, creates `EPUBNavigatorViewModel`, then calls the private initializer. The positions loader is saved as a closure. |
| 2 | `EPUBNavigatorViewModel.swift:46-79` [S8] | Creates `WebViewServer(scheme: "readium", ...)`, registers bundled assets and publication-resource routes. If the publication already has an HTTP base URL, it uses it directly. Registering these routes is not a WebKit load. |
| 3 | `EPUBNavigatorViewController.swift:327-371` [S7] | Saves model/location/reading order, initializes the parent controller, sets internal delegates/input callbacks and notification observers. No spread or `WKWebView` is constructed here. The public navigator delegate is weak (`:136`). |
| 4 | `EPUBNavigatorViewController.swift:382-391` [S9] | `viewDidLoad` schedules `Task { await initialize() }`. This is the asynchronous boundary before spread creation, not a delay inserted between a spread's initializer and its load. |
| 5 | `EPUBNavigatorViewController.swift:415-434` [S9] | `initialize()` awaits positions, creates/inserts the pagination view, applies settings, then calls `_reloadSpreads()`. Position computation can read native resources before any WebKit spread exists. |
| 6 | `EPUBNavigatorViewController.swift:600-635` [S10] | Builds spreads, selects the initial spread from the locator, and calls `paginationView.reloadAtIndex(...)`. |
| 7 | `PaginationView.swift:196-241` [S11] | Clears old views and load queue, calls `setCurrentIndex`, schedules current, next and previous views according to position counts, then calls `loadPages()`. |
| 8 | `PaginationView.swift:244-272` [S12] | A main-actor task runs `loadNextPage()`. For an unloaded index it invokes `delegate.paginationView(_:pageViewAtIndex:)`. This delegates to the navigator's factory. The returned view is inserted only after that factory finishes. |
| 9 | `EPUBNavigatorViewController.swift:1253-1267` [S1] | Chooses fixed/reflowable spread class and calls its initializer with `scripts: []`. **After** it returns, sets `spreadView.delegate = self`, obtains its content controller, calls the public delegate's `setupUserScripts`, then returns the view. |
| 10 | `EPUBSpreadView.swift:64-104` [S2] | During step 9's initializer, creates a fresh `WKWebViewConfiguration`, installs the `readium` scheme handler, constructs the `WebView` at line 84, calls `setupWebView()` at line 94, installs Readium scripts/messages, then synchronously invokes `loadSpread()` at line 104. |

The decisive call stack for a reflowable book is therefore:

```text
viewDidLoad
  Task -> initialize -> _reloadSpreads -> reloadAtIndex -> setCurrentIndex
    loadPages task -> loadNextPage
      navigator.paginationView(pageViewAtIndex:)
        EPUBReflowableSpreadView.init
          EPUBSpreadView.init
            WKWebViewConfiguration()
            WebView(..., configuration: config)
            setupWebView()
            registerJSMessages()
            loadSpread()
              EPUBReflowableSpreadView.loadSpread
                webView.load(URLRequest(...))     # first load submitted
        spreadView.delegate = self
        delegate.navigator(setupUserScripts: ...) # application rules added later
```

`WebView` is Readium's internal final `WKWebView` subclass. Its initializer calls `super.init(frame:configuration:)` and configures interaction/menu behavior; it does not supply another application pre-load hook. [S13]

### Reflowable versus fixed-layout details

**Reflowable.** The subclass initializer (`:20-34`) passes its bundled document-start script to the base initializer. `loadSpread()` (`:81-87`) resolves the first spread link through `viewModel.url(to:)` and calls `webView.load`. Both calls happen before the initializer returns to the factory. There is no `Task`, dispatch, continuation, wrapper-ready callback or superview requirement around that `load` call. `didMoveToSuperview` merely enables messages/sets the scroll delegate; it is not the trigger for initial document loading. [S2][S3][S14]

**Fixed layout.** The subclass initializes `isWrapperLoaded = false` and calls the base initializer (`:13-30`). The base initializer calls the subclass's `setupWebView()`; the override reads `fxl-spread-one.html` or `fxl-spread-two.html`, substitutes the bundled assets URL, and calls `loadHTMLString(..., baseURL: publicationBaseURL)` at line 61. The base initializer later calls `loadSpread()`, which initially returns because `isWrapperLoaded` is still false. On wrapper `didFinish` (`:145-152`), the subclass marks it loaded and calls `loadSpread()` again, which evaluates `spread.load(...)` (`:102-112`). [S4][S5]

The bundled wrapper's iframe elements start without a publication `src`; their script reference uses the substituted assets URL, normally `readium://assets/...`. The wrapper script calls the fixed-page loader, whose `setIframeSrc` assigns `_iframe.src = url`. Thus wrapper load and publication-iframe load are separate events. The trusted/local nature of this wrapper narrows the immediate risk for this branch, but does not change the observed source order or repair the reflowable branch. [S15][S16][S17]

### Why the existing delegate assignment is not the fix

The app already compiles its rules before constructing the navigator, then sets and strongly retains its delegate before publishing the controller to SwiftUI:

- `BookReader/Services/EPUBNavigationModel.swift:47-50`: compile `^https?://` block rule and reject compilation failure.
- `:71-86`: construct controller, construct delegate, assign `controller.delegate`, retain it with an associated object.
- `:89`: publish `navigator`; `BookReader/UI/EPUBReaderView.swift:126-130` returns the same controller from the representable.
- `BookReader/Services/EPUBNavigationModel.swift:199-200`: `setupUserScripts` adds the compiled list to the supplied content controller.

This avoids losing the weak delegate and installs the callback in time for view loading. It cannot move the callback ahead of the load inside the spread initializer. Reassigning the delegate sooner, zeroing preloads, waiting for the first visible page, or adding a second rule in the same callback does not reverse that order.

The earliest local publication HTML is normally delivered asynchronously through Readium's main-actor scheme server. Its `start` callback creates a task; publication-resource serving then awaits the registered handler and reads the resource. This may mean the late rule wins in some real executions. It is **not** proof of a documented WebKit barrier, especially for direct HTTP publication URLs or the fixed wrapper's already-submitted navigation. Do not claim actual transmission is synchronous, and do not claim the asynchronous scheme handler guarantees safety. [S18][S19]

## Preload, rotation and replacement web views

| Branch | Source trace | Consequence |
| --- | --- | --- |
| Initial/adjacent preloads | Controller `makePaginationView` at `:550-558`; pagination `:226-272`. [S20][S11][S12] | Current view is queued first, then forward and backward views. Loading is sequential across `await view.go(...)`, but every new view uses the same factory and initializer-before-hook order. |
| App preload values | `BookReader/Services/EPUBNavigationModel.swift:69-70` | Values `1` and `2` are **position counts**, not a promise of exactly one previous/two next chapters or a particular number of web views. With no positions the navigator sets counts to zero. Removing preloads still leaves the current spread's first-load problem. [S20] |
| Ordinary navigation | `PaginationView.goToIndex` and `setCurrentIndex`; factory at controller `:1253-1267`. [S21][S11][S1] | Reusing a loaded spread retains its existing content controller. A destination outside the loaded set constructs another web view with the same late-callback sequence. |
| Rotation that changes spread layout | Controller `viewWillTransition` `:465-470` -> model `viewSizeWillChange`/`updateSpread` `:278-302` -> main-queue invalidation `:157-166` -> controller `:966-967`, `:562-568`, `:580-635`. [S22][S23][S24][S10] | If the spread setting changes between single/double, pagination reloads, discards old views, and creates replacements through the same factory. Not every rotation necessarily allocates a web view. |
| Foreground after background rotation | Controller `didBecomeActive` `:400-412`. [S9] | Refreshes view size and performs a deferred reload if needed; replacement views follow the same route. |
| Web content process termination | Spread `webViewWebContentProcessDidTerminate` `:670-671` -> controller `spreadViewDidTerminate` `:1233-1234` -> `reloadSpreads()`. [S25][S26] | Recreated web views do not inherit an application rule list automatically from a destroyed view; they get the same per-new-spread callback, again after initialization submitted a load. |

The inspected EPUB implementation constructs its consuming web view in `EPUBSpreadView.init:84`, shared by the two spread subclasses. None of these replacement branches bypasses the problematic factory order.

## Native reads independent of WebKit

A `WKContentRuleList` is not a native-resource/network policy. Distinguish **network-capable APIs** from **network use actually selected for this local ZIP EPUB**.

| Stage | Exact implementation | Network consequence / public control |
| --- | --- | --- |
| Asset retrieval before navigator construction | `AssetRetriever` convenience initializer installs `DefaultResourceFactory`; its custom initializer accepts `ResourceFactory`, `FormatSniffer`, `ArchiveOpener`. Default resource factory includes both file and HTTP factories. [N1][N2] | Retrieving an HTTP asset can issue native requests before any navigator exists. The current app passes a `FileURL` (`EPUBNavigationModel.swift:54-56`), so this particular lookup selects a file resource. Public file-only resource factory is possible; changing only WebKit rules cannot constrain this stage. [N3] |
| Native remote resource reads | `HTTPResourceFactory.make` returns `HTTPResource`; `HTTPContainer` resolves links into it. `HTTPResource.headResponse` calls `client.fetch(HEAD)`; `stream` calls `client.stream` for GET/ranges. [N4][N5][N6] | Metadata/length reads as well as body reads can use the network independently of WebKit. A policy must reject before delegating to a networking client, not merely inspect a response. |
| The actual local EPUB parser | `DefaultPublicationParser` selects `EPUBParser()` separately from the HTTP-aware WebPub parser. `EPUBParser` parses using the asset container, wraps it in a deobfuscator and supplies content/positions/search services. [N7][N8] | This path does **not** install an automatic HTTP fallback for remote CSS/images referenced inside HTML. Minizip/ZIPFoundation container lookup requires a relative archive entry; an absent entry returns `nil`, not an HTTP fetch. Do not invent a native CSS fetch in this path. [N9][N10] |
| Positions before first spread | Controller `initialize:417` -> EPUB positions service `container[link.url()]`, archive properties/estimated length. [S9][N11] | Native reads occur before first WebKit content. For a local ZIP these are archive reads; with a network-backed/custom container they can become network reads. |
| Resources requested through `readium://` | Model `serve(href:)` -> `Publication.get` -> resource media type/Readium CSS injection -> scheme server `estimatedLength`/`read`. [N12][N13][S19] | The custom scheme is not itself evidence that the underlying resource is local. If a publication service/container returns an `HTTPResource`, the native read bypasses WebKit HTTP filtering. For the current unmodified local EPUB container, the inspected resolution path is local. |
| Search/content, covers and notes | Default content iterator obtains its resource from `publication.get`; resource-cover service reads `context.container`; navigator notes use `publication.get(...).read()`. [N14][N15][N16] | These are native resource consumers, not WebKit subresource loads. Their behavior depends on the publication's services/container. Search does not become a network sandbox merely because its displayed results are local. |
| Remote publication base URL | Model `:69-73` uses `publication.baseURL` directly. [S8] | This is a separate direct-WebKit remote-publication path. Native HTTP rejection alone will not stop WebKit from loading that URL. An offline product must not accidentally select this path. It is not the expected base for the app's local ZIP EPUB. |

`Publication.get` asks publication services before falling back to the container (`:115-119`). A wrapper on only the root container is therefore not a universal firewall for arbitrary custom services. The current default EPUB services and archive provenance matter. [N13]

The app's own `EPUBArchivePreflight.swift:45-62` validates archive/XML/OPF structure and rejects external XML entity declarations. It does not inspect every HTML/CSS/script reference to enforce a no-network rendering policy. `EPUBMetadataReader.swift:6-19` reads container/OPF bytes from the archive; it is not a WebKit renderer. Keeping preflight is necessary, but it is not a substitute for the missing rendering boundary.

### Public policy points that actually exist in 3.11.1

1. **Native deny client:** public `HTTPClient: Loggable` requires `stream(request:consume:)`; `fetch` delegates to that method. An implementation that immediately returns an explicit failure and never constructs/forwards to a network transport is a small, source-auditable native policy. Pass the same instance to `AssetRetriever` and `DefaultPublicationParser` as the app already passes its `DefaultHTTPClient`. This does not intercept `WKWebView` networking. [N17][N1][N7]
2. **Native pre-start delegate:** `DefaultHTTPClientDelegate.willStartRequest` can return a failure; `DefaultHTTPClient.stream` awaits it before `startTask` creates a URLSession data task. This is another existing pre-request point, but it retains a networking-capable implementation and has a weak delegate lifetime to manage. Do not confuse this with the EPUB navigator delegate. [N18][N19]
3. **File-only asset retrieval:** `AssetRetriever`'s custom initializer plus `FileResourceFactory` can remove HTTP capability at asset acquisition. It does not by itself remove HTTP resources returned by other services or WebKit URLs. [N1][N3]
4. **Pre-render resource transformation:** `PublicationOpener.onCreatePublication` receives mutable manifest/container/services before `builder.build()`. `Container.map`/`TransformingContainer` and `TransformingResource` can wrap resource bytes before serving. This is a real public customization point, not a guessed WebKit configuration API. [N20][N21][N22]
5. **WebKit callback:** public `setupUserScripts` exposes a `WKUserContentController`, but only at the late point already traced. The public `Configuration` contains preferences/defaults, editing actions/insets, preload counts, decorations, fonts, Readium CSS properties and debugging. Neither it nor the two public controller initializer paths provides an application `WKWebViewConfiguration` factory/before-load closure in this pin. Internal spread/view-model types are not external subclass extension points. [S1][S27][S2][S13]

The navigator's link delegates are not a replacement: `EPUBSpreadView.decidePolicyFor` only cancels and delegates `.linkActivated` navigations; other navigation types default to allow. `shouldNavigateToLink` and `presentExternalURL` are downstream link-handling callbacks, not filters for CSS/font/image/script requests or arbitrary script-driven navigation. [N23][N24]

## Bounded recommendation and missing prerequisite

### Recommended decision for the current approved behavior

**Do not enable EPUB on the strength of the current callback or a clean airplane-mode run.** Preserve `ImportService.swift:48-51` and `ReaderHostView.swift:26-43` locks until there is an accepted source-level boundary plus observed network evidence.

For the strict route, the smallest missing capability is **a supported pre-load WebKit policy point used for every newly created EPUB web view**. A pinned source change would need this order:

```text
compile policy successfully before opening
create/configure WKUserContentController with policy
assign it to WKWebViewConfiguration
construct WKWebView with that configuration
perform any fixed wrapper or reflowable document load
```

The exact construction boundary is `EPUBSpreadView.swift:74-84`. A change that merely moves line 104's `loadSpread()` out of the initializer is incomplete: fixed-layout `setupWebView()` already calls `loadHTMLString` at line 61. Both routes and every preload/recreation must use the policy. Apple documents content-controller setup before web-view creation; `add(_:)` documents applying rules, but does not promise retroactive protection of an already-submitted navigation. [APPLE1][APPLE2]

**Consequence requiring approval:** maintaining a pinned Readium source adjustment/fork changes the dependency/protection maintenance responsibility. This report does not authorize or implement that change, upgrade the pin, or select another library. Adding a direct network-denying `HTTPClient` is still needed for the separate native boundary; it cannot resolve this missing WebKit hook.

### Existing-API alternative, not an accepted safety conclusion

A public-only investigation could use `PublicationOpener.onCreatePublication` to wrap every served HTML/XHTML resource and deliver a restrictive CSP before any publisher-controlled resource-bearing markup. Because the scheme server reads the wrapped resource before returning bytes, this is genuinely earlier than the document parser seeing the publisher content. [N20][N21][N22][N12][S19]

However, this is a **different protection design**, not a repair of `setupUserScripts` timing:

- It must preserve Readium's required scripts/assets and agreed EPUB behavior. A blanket script ban or disabled publisher content can break real books rather than complete the original feature.
- It needs an explicitly justified policy for nested frames, local script execution, navigation and every served HTML media type. A CSP meta tag cannot be assumed to constrain all subsequent top-level navigation or native resources.
- Native fixed-layout wrapper HTML is loaded from a bundle with `loadHTMLString`, not from the publication container being transformed. Its current references are controlled/local, but it is outside that transformation boundary.
- CSP meta placement matters: the W3C specification states that content preceding the meta policy is not protected and identifies prefetched resources as a caveat. Rewriting/sanitizing or inserting after existing markup without proving ordering is not sufficient. Actual iOS 15 WebKit handling for this custom-scheme XHTML pipeline remains UNVERIFIED. [CSP]

Therefore, if a Readium source adjustment is not approved, the specific prerequisite is an approved resource-policy design and its iOS 15 observation evidence. Do not silently ship a policy rewrite, claim it is a pre-load WebKit configuration hook, or reduce support to a narrow EPUB subset without explicit acceptance. No additional dependency is required merely to establish these public API facts.

## One meaningful hostile-EPUB observation scenario

**Proposed, not run:** an online cold-open plus lifecycle test, parameterized with reflowable and fixed-layout versions of the same controlled EPUB fixture. The two renditions exercise different first-load paths; one reflowable result cannot stand in for the fixed wrapper/iframe branch. This is one acceptance protocol, not another library comparison.

### Controlled fixture and observation surfaces

- Use a local DRM-free EPUB with eight short spine documents, local navigation and visible local sentinels such as `FIRST`, `NEXT`, `LAST`. Give every spine document distinct URLs/tokens for its remote references so first load, preloads and later navigation can be separated. No private/user content is needed.
- Put a remote stylesheet and remote script early in each document head. Also use local CSS containing an external `@import`, a consumed `@font-face`, and an image/background reference; include a direct remote `<img>`. Use unique controlled HTTPS hosts/paths for each vector. The fixture's inline/local script can update a local DOM sentinel and attempt benign fetch/image requests so script execution is observable without using the remote response as the only proof.
- Include a resource URL on a controlled redirect origin which responds with HTTP 302 to a second controlled origin. Record both the initial and final endpoints. **Even the first request is failure**; blocking only the redirect destination does not satisfy no-outbound.
- Serve valid CSS/font/image/script MIME types and suitable noncredentialed font CORS responses; use publicly trusted HTTPS. Add an HTTP variation only as supplemental coverage: ATS/TLS failure is not evidence that the EPUB policy blocked a request. Give all URLs a fresh run token and use `no-store`; no-cache observations must not depend on deleting the user's existing app/library.
- Observe controlled authoritative-DNS logs and origin access logs, recording all methods including HEAD/OPTIONS/GET. Capture device traffic with the Apple-supported packet-trace workflow, or the simulator's relevant Mac interface. A device/simulator WebKit content process can issue traffic outside an app-only `URLSession` observer; an app `URLProtocol`/client counter alone is insufficient. [APPLE3]
- Use a debug observation build or debugger logpoints to record, for each new web-view/content-controller identity: rule attachment, first `loadRequest`/`loadHTMLString` submission, first local content render, navigation and rotation times. Do not log book text or credentials. These markers correlate the request window; they are not themselves proof that no network traffic occurred.

### Execution and controls

1. **Establish a positive control in an isolated lab harness, not a shipping bypass.** With the same pinned Readium, fixture and reading preferences but without the candidate policy, confirm the controlled HTTPS endpoints receive each expected CSS/font/image/script/redirect request and that packet/DNS observation sees them. A font optimized away by the active style preferences or a script not executed makes that vector inconclusive; adjust the fixture/control before treating an empty log as a pass.
2. Start fresh-token DNS, origin and packet observation **before app launch/import/open**. Keep networking enabled. Open the candidate build through the actual import and reader entrypoint once that test path is authorized. The currently locked release cannot yield a rendering pass merely by showing the locked screen and making no requests.
3. Wait for real local first content, confirm the first sentinel/usable page, and observe a defined idle window. Correlate the first-load and rule-attachment markers. For the strict configuration route, every consuming web view must have rules attached before its first load submission. For a separately approved resource-policy route, capture its policy-before-bytes boundary instead of falsely claiming the load order changed.
4. Navigate next/back, jump via contents to the last spine item beyond the initial preload window, rotate portrait/landscape, background/foreground, close/reopen at the saved location, and observe another defined idle window. Confirm content sentinels and saved-location behavior throughout. If claiming coverage of web-content-process recreation, exercise and record an actual recreation separately; ordinary rotation is not proof that it happened.
5. Finish with a positive control request in a separate labeled control interval to confirm the observation path still works. Preserve fixture bytes/hash, policy/configuration, app revision, Readium SHA, OS/WebKit version, device/simulator identity, timestamps, view-event log, screenshots, DNS/access logs and packet capture.

**Pass criterion for the exercised boundary:** actual book content and navigation/reopen work; the positive controls demonstrate every intended remote vector; zero fixture-related DNS resolutions, outbound connection attempts or origin requests occur during candidate import/open, before first content, preload, navigation, rotation and reopen windows. A canceled request visible in the capture, an initial redirect hit, a missing positive control, or a blank/non-rendering book is not a pass. A finite clean run supports only the exercised OS/layout/lifecycle paths, not a mathematical guarantee for every hostile EPUB or all iOS versions.

**Current result: UNVERIFIED.** No hostile fixture, debugger trace, origin log or packet capture was produced by this investigation. The source defect and policy choices must not be confused with completed product acceptance.

## Pinned source index

The line anchors below all refer to the app's exact Readium commit. Apple/W3C references describe platform contracts, not the app's observed runtime.

[PIN]: https://api.github.com/repos/readium/swift-toolkit/git/trees/3.11.1?recursive=1
[GUIDE]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/docs/Guides/Open%20Publication.md
[CONTRIBUTING]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/CONTRIBUTING.md
[S1]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L1252-L1267
[S2]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBSpreadView.swift#L64-L104
[S3]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBReflowableSpreadView.swift#L20-L87
[S4]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBFixedSpreadView.swift#L13-L62
[S5]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBFixedSpreadView.swift#L102-L152
[S6]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L278-L307
[S7]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L327-L371
[S8]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewModel.swift#L46-L79
[S9]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L382-L434
[S10]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L580-L635
[S11]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/Toolkit/PaginationView.swift#L196-L241
[S12]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/Toolkit/PaginationView.swift#L244-L272
[S13]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/Toolkit/WebView.swift#L12-L33
[S14]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBSpreadView.swift#L152-L170
[S15]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/Assets/fxl-spread-one.html#L31-L32
[S16]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/Assets/fxl-spread-two.html#L65-L74
[S17]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/Scripts/src/fixed-page.js#L159-L165
[S18]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/WebViewServer.swift#L15-L25
[S19]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/WebViewServer.swift#L124-L266
[S20]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L550-L568
[S21]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/Toolkit/PaginationView.swift#L327-L341
[S22]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L465-L470
[S23]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewModel.swift#L278-L302
[S24]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewModel.swift#L157-L166
[S25]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBSpreadView.swift#L670-L671
[S26]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L1233-L1234
[S27]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L47-L136
[N1]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/Data/Asset/AssetRetriever.swift#L37-L59
[N2]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/Data/Resource/ResourceFactory.swift#L9-L34
[N3]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/File/FileResourceFactory.swift#L9-L17
[N4]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/HTTP/HTTPResourceFactory.swift#L9-L23
[N5]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/HTTP/HTTPContainer.swift#L9-L39
[N6]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/HTTP/HTTPResource.swift#L24-L82
[N7]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Streamer/Parser/DefaultPublicationParser.swift#L12-L24
[N8]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Streamer/Parser/EPUB/EPUBParser.swift#L39-L78
[N9]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/ZIP/Minizip/MinizipContainer.swift#L69-L76
[N10]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/ZIP/ZIPFoundation/ZIPFoundationContainer.swift#L64-L74
[N11]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Streamer/Parser/EPUB/Services/EPUBPositionsService.swift#L44-L118
[N12]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewModel.swift#L169-L198
[N13]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Publication/Publication.swift#L108-L119
[N14]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Publication/Services/Content/Iterators/PublicationContentIterator.swift#L89-L107
[N15]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Publication/Services/Cover/ResourceCoverService.swift#L69-L78
[N16]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L1157-L1179
[N17]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/HTTP/HTTPClient.swift#L10-L45
[N18]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/HTTP/DefaultHTTPClient.swift#L23-L40
[N19]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/HTTP/DefaultHTTPClient.swift#L186-L253
[N20]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Streamer/PublicationOpener.swift#L114-L138
[N21]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/Data/Container/TransformingContainer.swift#L9-L56
[N22]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Shared/Toolkit/Data/Resource/TransformingResource.swift#L9-L37
[N23]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBSpreadView.swift#L651-L667
[N24]: https://github.com/readium/swift-toolkit/blob/9a8c094b72245fd27043c9d298005e5c78b32a01/Sources/Navigator/EPUB/EPUBNavigatorViewController.swift#L1104-L1144
[APPLE1]: https://developer.apple.com/documentation/webkit/wkusercontentcontroller
[APPLE2]: https://developer.apple.com/documentation/webkit/wkusercontentcontroller/add(_:)
[APPLE3]: https://developer.apple.com/documentation/network/recording-a-packet-trace
[CSP]: https://www.w3.org/TR/2016/REC-CSP2-20161215/#delivery-html-meta-element
