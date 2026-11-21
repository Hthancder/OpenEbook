import Combine
import Foundation
import ReadiumShared
import ReadiumNavigator
import ReadiumStreamer
import WebKit
import UIKit

@MainActor
final class EPUBNavigationModel: ObservableObject {
    @Published var navigator: EPUBNavigatorViewController?
    @Published var errorMessage: String?
    @Published var readerMessage: String?
    @Published var contents: [Link] = []
    @Published var bookmarks: [ReaderBookmark] = []
    @Published var isSearchable = false
    @Published var isReflowable = false
    @Published var fontSize = 18.0 { didSet { updatePreferences() } }
    @Published var lineSpacing = 1.0 { didSet { updatePreferences() } }
    @Published var backgroundName = "paper" { didSet { updatePreferences() } }

    private var publication: Publication?
    private var preferences = EPUBPreferences.empty
    private var onLocation: ((Locator) -> Void)?
    private var searchTask: Task<Void, Never>?
    private let contentRuleListStore = WKContentRuleListStore.default()

    func initialLocatorJSON(for book: BookRecord) -> String? {
        guard let json = book.locatorJSON, let data = json.data(using: .utf8),
              let location = try? JSONDecoder().decode(ReadingLocation.self, from: data),
              case let .epub(locatorJSON, version) = location.position, version == 1 else { return nil }
        return locatorJSON
    }

    func open(url: URL, initialLocatorJSON: String?, textSize: Double, model: AppModel, book: BookRecord) {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Không tìm thấy bản sao sách."
            return
        }
        onLocation = { [weak model] locator in
            guard let json = try? locator.jsonString() else { return }
            model?.saveLocation(ReadingLocation(position: .epub(locatorJSON: json, locatorVersion: 1)), for: book)
        }
        let initialLocator = initialLocatorJSON.flatMap { try? Locator(legacyJSONString: $0) }
        Task { @MainActor in
            do {
                guard let contentRuleListStore else { throw ImportFailure.networkPolicy }
                let policy = "[{\"trigger\":{\"url-filter\":\"^https?://\",\"url-filter-is-case-sensitive\":false},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^wss?://\",\"url-filter-is-case-sensitive\":false},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^ftp://\",\"url-filter-is-case-sensitive\":false},\"action\":{\"type\":\"block\"}}]"
                let rules = try await contentRuleListStore.compileContentRuleList(forIdentifier: "BookReader.BlockExternal", encodedContentRuleList: policy)
                guard let rules else { throw ImportFailure.networkPolicy }
                let httpClient = EPUBOfflineHTTPClient()
                let retriever = AssetRetriever(httpClient: httpClient)
                let opener = PublicationOpener(parser: DefaultPublicationParser(httpClient: httpClient, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory()))
                guard let fileURL = url.fileURL else { throw ImportFailure.invalid }
                let asset: Asset
                switch await retriever.retrieve(url: fileURL) {
                case .success(let value): asset = value
                case .failure: throw ImportFailure.invalid
                }
                let publication: Publication
                switch await opener.open(asset: asset, allowUserInteraction: false) {
                case .success(let value): publication = value
                case .failure: throw ImportFailure.protected
                }
                guard !publication.readingOrder.isEmpty else { throw ImportFailure.invalid }

                let loadedPreferences = EPUBPreferences(fontSize: 1, lineHeight: 1, publisherStyles: false)
                var config = EPUBNavigatorViewController.Configuration(preferences: loadedPreferences)
                config.offlineContentRuleList = rules
                config.preloadPreviousPositionCount = 1
                config.preloadNextPositionCount = 2
                let controller = try EPUBNavigatorViewController(publication: publication, initialLocation: initialLocator, config: config)
                let delegate = EPUBSafeNavigatorDelegate(
                    onLocation: { [weak self] in self?.onLocation?($0) },
                    onError: { [weak self] error in
                        switch error {
                        case .copyForbidden:
                            self?.readerMessage = "Giấy phép của sách không cho phép sao chép văn bản."
                        @unknown default:
                            self?.readerMessage = "Đã xảy ra lỗi khi đọc EPUB."
                        }
                    }
                )
                controller.delegate = delegate
                objc_setAssociatedObject(controller, &epubDelegateAssociationKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

                self.publication = publication
                self.preferences = loadedPreferences
                self.navigator = controller
                self.contents = publication.manifest.tableOfContents
                self.isSearchable = publication.isSearchable
                self.isReflowable = publication.metadata.layout != .fixed
                self.fontSize = min(max(textSize.isFinite ? textSize : 18, 14), 30)
                self.bookmarks = Self.decodeBookmarks(book.bookmarkJSON)
            } catch let failure as ImportFailure { errorMessage = failure.message }
            catch { errorMessage = "Không thể mở EPUB trên thiết bị này." }
        }
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard isSearchable, let publication, let navigator else {
            readerMessage = "Sách này không cung cấp tìm kiếm."
            return
        }
        searchTask = Task { @MainActor in
            let result = await publication.search(query: value, options: SearchOptions(caseSensitive: false, diacriticSensitive: false))
            guard !Task.isCancelled else { return }
            switch result {
            case .failure:
                readerMessage = "Không thể tìm trong sách."
            case .success(let iterator):
                do {
                    guard let page = try await iterator.next().get(), let locator = page.locators.first else {
                        readerMessage = "Không tìm thấy kết quả."
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await navigator.go(to: locator)
                    readerMessage = "Đã đến kết quả đầu tiên."
                } catch { readerMessage = "Không thể đọc kết quả tìm kiếm." }
            }
        }
    }

    func navigate(to link: Link) {
        guard let navigator else { return }
        Task { await navigator.go(to: link) }
    }

    func addCurrentBookmark(for book: BookRecord, model: AppModel) {
        guard let navigator, let locator = navigator.currentLocation,
              let json = try? locator.jsonString() else {
            readerMessage = "Vị trí đọc chưa sẵn sàng để đánh dấu."
            return
        }
        let location = ReadingLocation(position: .epub(locatorJSON: json, locatorVersion: 1))
        model.addBookmark(location, title: locator.title ?? locator.href.string, for: book)
        bookmarks = Self.decodeBookmarks(model.library.book(id: book.id)?.bookmarkJSON)
    }

    func showBookmarks(for book: BookRecord, model: AppModel) {
        bookmarks = Self.decodeBookmarks(model.library.book(id: book.id)?.bookmarkJSON)
        if bookmarks.isEmpty { readerMessage = "Chưa có dấu trang." }
    }

    func navigate(to bookmark: ReaderBookmark) {
        guard let navigator, let data = bookmark.locatorJSON.data(using: .utf8),
              let location = try? JSONDecoder().decode(ReadingLocation.self, from: data),
              case let .epub(json, version) = location.position, version == 1,
              let locator = try? Locator(jsonString: json) else { return }
        Task { await navigator.go(to: locator) }
    }

    private func updatePreferences() {
        guard let navigator else { return }
        guard isReflowable else { return }
        let safeSize = fontSize.isFinite ? min(max(fontSize, 14), 30) : 18
        let safeLineHeight = lineSpacing.isFinite ? min(max(lineSpacing, 1), 1.8) : 1
        let theme: Theme? = switch backgroundName {
        case "dark": .dark
        case "light": .light
        default: .sepia
        }
        preferences = EPUBPreferences(fontSize: safeSize / 18, lineHeight: safeLineHeight, publisherStyles: false, theme: theme)
        navigator.submitPreferences(preferences)
    }

    private static func decodeBookmarks(_ json: String?) -> [ReaderBookmark] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ReaderBookmark].self, from: data)) ?? []
    }
}

private var epubDelegateAssociationKey = "book-reader-epub-delegate" as NSString

@MainActor
private final class EPUBSafeNavigatorDelegate: NSObject, EPUBNavigatorDelegate {
    private let onLocation: (Locator) -> Void
    private let onError: (NavigatorError) -> Void

    init(onLocation: @escaping (Locator) -> Void, onError: @escaping (NavigatorError) -> Void) {
        self.onLocation = onLocation
        self.onError = onError
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        onLocation(locator)
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        onError(error)
    }

    func navigator(_ navigator: VisualNavigator, shouldNavigateToLink link: Link) -> Bool {
        if let url = URL(string: link.href), url.scheme != nil {
            return false
        }
        return true
    }
    func navigator(_ navigator: Navigator, presentExternalURL url: URL) {}
}
