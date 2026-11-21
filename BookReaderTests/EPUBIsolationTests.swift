import Foundation
import Network
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import ReadiumZIPFoundation
import UIKit
import WebKit
import XCTest
@testable import BookReader

/// Runtime proof for the offline EPUB boundary. This intentionally uses a real
/// Readium navigator and real WebKit views; source inspection alone cannot
/// prove that the first spread was isolated.
final class EPUBIsolationTests: XCTestCase {
    func testOfflineHTTPClientFailsClosedWithoutConsuming() async throws {
        let client = EPUBOfflineHTTPClient()
        var consumed = false
        let result = await client.stream(request: URL(string: "https://example.invalid/outside")!) { _, _ in
            consumed = true
            return .success(())
        }

        guard case .failure(.security) = result else {
            return XCTFail("The offline HTTP client must return a security failure")
        }
        XCTAssertFalse(consumed, "A rejected request must not invoke the body consumer")
    }

    @MainActor
    func testEPUBNavigatorBlocksHostileFirstLoadAndLaterWebViews() async throws {
        let positive = try await TrafficObserver()
        let control = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        defer {
            control.stopLoading()
            control.navigationDelegate = nil
            control.removeFromSuperview()
            positive.stop()
        }
        let controlDelegate = NavigationWaiter()
        control.navigationDelegate = controlDelegate
        control.load(URLRequest(url: positive.url(path: "/control")))
        let controlLoaded = await controlDelegate.wait(timeout: 15)
        XCTAssertTrue(controlLoaded, "The connected positive control did not finish loading")
        let positiveSawRequest = await positive.waitForRequest(timeout: 15)
        XCTAssertTrue(positiveSawRequest, "The connected positive control must produce real observer traffic")
        positive.stop()
        let dnsControl = URL(string: "https://bookreader-control-\(UUID().uuidString.lowercased()).example.com/")!
        control.load(URLRequest(url: dnsControl))
        try await Task.sleep(nanoseconds: 3_000_000_000)
        control.stopLoading()
        await Task.yield()

        let rules = try await compileOfflineRules()
        for fixedLayout in [false, true] {
            try await verifyHostilePublication(rules: rules, fixedLayout: fixedLayout)
        }
    }

    @MainActor
    private func verifyHostilePublication(rules: WKContentRuleList, fixedLayout: Bool) async throws {
        let strict = try await TrafficObserver()
        defer { strict.stop() }
        let fixtureURL = try await makeFixture(remotePort: strict.port, fixedLayout: fixedLayout)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let publication = try await openPublication(at: fixtureURL)

        var firstWindow: PresentedNavigator? = try await presentNavigator(publication: publication, rules: rules)
        defer {
            if let firstWindow { teardown(firstWindow) }
        }
        guard let first = firstWindow else { throw ImportFailure.invalid }
        let firstLocal = await waitForJavaScript(first.navigator, "document.body && document.body.innerText.includes('LOCAL-CHAPTER-1')", timeout: 20)
        XCTAssertTrue(firstLocal, "The first local chapter did not render")
        let firstHrefIsLocal = await waitForJavaScript(first.navigator, "document.location.href.indexOf('http://') !== 0 && document.location.href.indexOf('https://') !== 0", timeout: 5)
        XCTAssertTrue(firstHrefIsLocal, "The first resource navigated to an external URL")
        let firstScriptsBlocked = await waitForJavaScript(first.navigator, "window.authorRan === undefined && window.remoteRan === undefined && window.fetchRan === undefined && window.wsRan === undefined && window.formRan === undefined && window.locationRan === undefined", timeout: 5)
        XCTAssertTrue(firstScriptsBlocked, "Publisher or remote active-attempt scripts executed")

        guard publication.readingOrder.count >= 4 else { throw ImportFailure.invalid }
        let movedToTwo = await first.navigator.go(to: publication.readingOrder[1])
        XCTAssertTrue(movedToTwo, "The second local chapter could not be selected")
        let secondLocal = await waitForJavaScript(first.navigator, "document.body && document.body.innerText.includes('LOCAL-CHAPTER-2')", timeout: 20)
        XCTAssertTrue(secondLocal, "The second local chapter did not render")
        let secondScriptsBlocked = await waitForJavaScript(first.navigator, "window.authorRan === undefined && window.remoteRan === undefined && window.fetchRan === undefined && window.wsRan === undefined && window.formRan === undefined && window.locationRan === undefined", timeout: 5)
        XCTAssertTrue(secondScriptsBlocked, "Active attempts executed after a same-webview chapter change")
        let movedToThree = await first.navigator.go(to: publication.readingOrder[2])
        XCTAssertTrue(movedToThree, "The third local chapter could not be selected")
        let thirdLocal = await waitForJavaScript(first.navigator, "document.body && document.body.innerText.includes('LOCAL-CHAPTER-3')", timeout: 20)
        XCTAssertTrue(thirdLocal, "The third local chapter did not render")

        let movedToSVG = await first.navigator.go(to: publication.readingOrder[3])
        XCTAssertTrue(movedToSVG, "The standalone SVG resource could not be selected")
        let svgLocal = await waitForJavaScript(first.navigator, "document.documentElement.textContent.includes('LOCAL-SVG')", timeout: 20)
        XCTAssertTrue(svgLocal, "The standalone SVG did not render local content")
        let svgScriptsBlocked = await waitForJavaScript(first.navigator, "window.authorRan === undefined && window.remoteRan === undefined", timeout: 5)
        XCTAssertTrue(svgScriptsBlocked, "The standalone SVG executed publisher scripts")
        teardown(first)
        firstWindow = nil
        let secondWindow = try await presentNavigator(publication: publication, rules: rules)
        defer { teardown(secondWindow) }
        let recreatedLocal = await waitForJavaScript(secondWindow.navigator, "document.body && document.body.innerText.includes('LOCAL-CHAPTER-1')", timeout: 20)
        XCTAssertTrue(recreatedLocal, "The recreated web view did not render local chapter one")
        let recreatedScriptsBlocked = await waitForJavaScript(secondWindow.navigator, "window.authorRan === undefined && window.remoteRan === undefined && window.fetchRan === undefined && window.wsRan === undefined && window.formRan === undefined && window.locationRan === undefined", timeout: 5)
        XCTAssertTrue(recreatedScriptsBlocked, "The recreated web view did not retain the offline policy")

        let quiescent = await strict.waitForQuiescence(timeout: 2, quietInterval: 0.2)
        XCTAssertTrue(quiescent, "Strict observer did not reach bounded quiescence")
        XCTAssertEqual(strict.requestCount, 0, "No external HTTP, HTTPS, WS, or WSS request may reach the strict observer")
        XCTAssertEqual(strict.connectionCount, 0, "No external connection, including failed TLS or WebSocket handshakes, may reach the strict observer")
    }

    private func compileOfflineRules() async throws -> WKContentRuleList {
        let policy = """
        [
          {"trigger":{"url-filter":"^https?://","url-filter-is-case-sensitive":false},"action":{"type":"block"}},
          {"trigger":{"url-filter":"^wss?://","url-filter-is-case-sensitive":false},"action":{"type":"block"}},
          {"trigger":{"url-filter":"^ftp://","url-filter-is-case-sensitive":false},"action":{"type":"block"}}
        ]
        """
        guard let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "BookReader.EPUBIsolation.\(UUID().uuidString)",
            encodedContentRuleList: policy
        ) else {
            throw ImportFailure.networkPolicy
        }
        return rules
    }

    private func openPublication(at url: URL) async throws -> Publication {
        let client = EPUBOfflineHTTPClient()
        let retriever = AssetRetriever(httpClient: client)
        let opener = PublicationOpener(
            parser: DefaultPublicationParser(httpClient: client, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory())
        )
        guard let fileURL = url.fileURL else { throw ImportFailure.invalid }
        let asset: Asset
        switch await retriever.retrieve(url: fileURL) {
        case .success(let value): asset = value
        case .failure: throw ImportFailure.invalid
        }
        switch await opener.open(asset: asset, allowUserInteraction: false) {
        case .success(let value): return value
        case .failure: throw ImportFailure.invalid
        }
    }

    private struct PresentedNavigator {
        let window: UIWindow
        let host: UIViewController
        let navigator: EPUBNavigatorViewController
    }

    @MainActor
    private func presentNavigator(publication: Publication, rules: WKContentRuleList) async throws -> PresentedNavigator {
        var config = EPUBNavigatorViewController.Configuration()
        config.offlineContentRuleList = rules
        let navigator = try EPUBNavigatorViewController(publication: publication, initialLocation: nil, config: config)
        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.addChild(navigator)
        navigator.view.frame = host.view.bounds
        navigator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(navigator.view)
        navigator.didMove(toParent: host)
        return PresentedNavigator(window: window, host: host, navigator: navigator)
    }

    @MainActor
    private func teardown(_ presented: PresentedNavigator) {
        presented.navigator.willMove(toParent: nil)
        presented.navigator.view.removeFromSuperview()
        presented.navigator.removeFromParent()
        presented.window.rootViewController = nil
        presented.window.resignKey()
        presented.window.isHidden = true
    }

    private func waitForJavaScript(_ navigator: EPUBNavigatorViewController, _ script: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .success(let value) = await navigator.evaluateJavaScript(script),
               (value as? Bool == true || (value as? NSNumber)?.boolValue == true) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func makeFixture(remotePort: UInt16, fixedLayout: Bool) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EPUBIsolation-\(UUID().uuidString).epub")
        let archive = try await Archive(url: url, accessMode: .create)
        let remote = "http://localhost:\(remotePort)"
        let dnsHostname = "bookreader-strict-\(UUID().uuidString.lowercased()).example.com"
        let layout = fixedLayout ? "pre-paginated" : "reflowable"
        let entries: [(String, String)] = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<?xml version=\"1.0\"?><container xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>"),
            ("OEBPS/content.opf", "<?xml version=\"1.0\"?><package version=\"3.0\" unique-identifier=\"book-id\" xmlns=\"http://www.idpf.org/2007/opf\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><metadata><dc:identifier id=\"book-id\">urn:uuid:epub-isolation</dc:identifier><dc:title>Isolation Fixture</dc:title><dc:language>en</dc:language><meta property=\"rendition:layout\">\(layout)</meta><meta property=\"rendition:spread\">none</meta></metadata><manifest><item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/><item id=\"one\" href=\"chapter1.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"two\" href=\"chapter2.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"three\" href=\"chapter3.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"svg\" href=\"standalone.svg\" media-type=\"image/svg+xml\"/><item id=\"css\" href=\"hostile.css\" media-type=\"text/css\"/></manifest><spine><itemref idref=\"one\"/><itemref idref=\"two\"/><itemref idref=\"three\"/><itemref idref=\"svg\"/></spine></package>"),
            ("OEBPS/nav.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><body><nav epub:type=\"toc\"><ol><li><a href=\"chapter1.xhtml\">One</a></li><li><a href=\"chapter2.xhtml\">Two</a></li><li><a href=\"chapter3.xhtml\">Three</a></li></ol></nav></body></html>"),
            ("OEBPS/chapter1.xhtml", hostileChapter(marker: "LOCAL-CHAPTER-1", remote: remote, dnsHostname: dnsHostname)),
            ("OEBPS/chapter2.xhtml", hostileChapter(marker: "LOCAL-CHAPTER-2", remote: remote, dnsHostname: dnsHostname)),
            ("OEBPS/chapter3.xhtml", hostileChapter(marker: "LOCAL-CHAPTER-3", remote: remote, dnsHostname: dnsHostname)),
            ("OEBPS/standalone.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"600\" height=\"800\" viewBox=\"0 0 600 800\"><text x=\"20\" y=\"40\">LOCAL-SVG</text><image href=\"\(remote)/standalone-image.png\" width=\"20\" height=\"20\"/><script>window.authorRan = true; fetch('\(remote)/svg-fetch');</script><image href=\"https://\(dnsHostname)/svg.png\" width=\"20\" height=\"20\"/></svg>"),
            ("OEBPS/hostile.css", "@import url('\(remote)/import.css'); @font-face {font-family: hostile; src: url('\(remote)/font.woff2')} body {font-family: hostile; background-image: url('\(remote)/background.png')}"),
        ]
        for (path, text) in entries {
            let data = Data(text.utf8)
            try await archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                return start < end ? Data(data[start..<end]) : Data()
            }
        }
        return url
    }

    private func hostileChapter(marker: String, remote: String, dnsHostname: String) -> String {
        let socket = remote.replacingOccurrences(of: "http://", with: "ws://")
        let secureRemote = remote.replacingOccurrences(of: "http://", with: "https://")
        return """
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <meta name="viewport" content="width=600,height=800" />
            <meta http-equiv="refresh" content="0;url=\(remote)/meta-refresh" />
            <link rel="preconnect" href="\(remote)" />
            <link rel="dns-prefetch" href="//\(dnsHostname)" />
            <link rel="preconnect" href="https://\(dnsHostname)" />
            <link rel="stylesheet" href="hostile.css" />
            <link rel="stylesheet" href="\(remote)/remote.css" />
            <?xml-stylesheet type="text/css" href="\(remote)/external.xml.css"?>
            <script src="\(remote)/remote.js"></script>
          </head>
          <body>
            <p>\(marker)</p>
            <img src="\(remote)/remote.png" />
            <img src="\(secureRemote)/tls-image.png" />
            <img src="https://\(dnsHostname)/dns-image.png" />
            <iframe src="\(remote)/frame.xhtml"></iframe>
            <object data="\(remote)/object.svg" type="image/svg+xml"></object>
            <svg xmlns="http://www.w3.org/2000/svg"><image href="\(remote)/inline.svg" /></svg>
            <form action="\(remote)/submit" method="post"><input name="attempt" value="active" /><button type="submit">submit</button></form>
            <script>
              window.authorRan = true;
              fetch("\(remote)/fetch").then(() => window.fetchRan = true);
              new WebSocket("\(socket)/socket");
              new WebSocket("\(socket.replacingOccurrences(of: "ws://", with: "wss://"))/secure-socket");
              new Worker("\(remote)/worker.js");
              navigator.sendBeacon("\(remote)/beacon", "attempt");
              document.forms[0].submit();
              window.location = "\(remote)/script-navigation";
              window.formRan = true;
            </script>
          </body>
        </html>
        """
    }
}

private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private let lock = NSLock()
    private var finished = false

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lock.lock(); finished = true; lock.unlock()
    }

    func wait(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock(); let value = finished; lock.unlock()
            if value { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
}

private final class TrafficObserver {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "BookReader.EPUBIsolation.Traffic")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var requests = 0
    private var connectionsSeen = 0
    private var ready = false

    var port: UInt16 { listener.port?.rawValue ?? 0 }
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests }
    var connectionCount: Int { lock.lock(); defer { lock.unlock() }; return connectionsSeen }

    init() async throws {
        listener = try NWListener(using: .tcp, on: .any)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.lock.lock(); let shouldResume = !self.ready; self.ready = true; self.lock.unlock()
                    if shouldResume { continuation.resume() }
                case .failed(let error):
                    self.lock.lock(); let shouldResume = !self.ready; self.ready = true; self.lock.unlock()
                    if shouldResume { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
    }

    func url(path: String) -> URL {
        URL(string: "http://localhost:\(port)\(path)")!
    }
    func waitForRequest(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if requestCount > 0 { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    func waitForQuiescence(timeout: TimeInterval, quietInterval: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastCount = connectionCount + requestCount
        var quietSince = Date()
        while Date() < deadline {
            let current = connectionCount + requestCount
            if current != lastCount {
                lastCount = current
                quietSince = Date()
            } else if Date().timeIntervalSince(quietSince) >= quietInterval {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let owned = connections
        connections.removeAll()
        lock.unlock()
        owned.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock(); connectionsSeen += 1; connections.append(connection); lock.unlock()
        connection.stateUpdateHandler = { _ in }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, _ in
            guard let self, let connection else { return }
            if let data, !data.isEmpty {
                self.lock.lock(); self.requests += 1; self.lock.unlock()
                self.respond(to: connection, request: String(decoding: data, as: UTF8.self))
            }
        }
    }

    private func respond(to connection: NWConnection, request: String) {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let body: Data
        let type: String
        if path.hasSuffix(".css") { body = Data("body { color: red }".utf8); type = "text/css" }
        else if path.hasSuffix(".js") { body = Data("window.remoteRan = true".utf8); type = "application/javascript" }
        else if path.hasSuffix(".png") { body = Data([137, 80, 78, 71, 13, 10, 26, 10]); type = "image/png" }
        else { body = Data("<html><body>remote</body></html>".utf8); type = "text/html" }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak connection] _ in
            connection?.cancel()
        })
    }
}
