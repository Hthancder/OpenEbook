import SwiftUI
import PDFKit

struct PDFOutlineEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let page: Int
}

struct PDFReaderView: View {
    let url: URL
    let initialLocation: ReadingLocation?
    let bookmarks: [ReaderBookmark]
    let onPageChange: (Int, Double) -> Void
    let onBookmark: (ReadingLocation, String) -> Void
    @State private var currentPage = 0
    @State private var pageCount = 0
    @State private var canSearch = false
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var searchResults: [PDFSelection] = []
    @State private var selectedSearchResult = 0
    @State private var showBookmarks = false
    @State private var outline: [PDFOutlineEntry] = []
    @State private var pendingPage: Int?

    private var initialPage: Int {
        guard case let .pdf(page, _, _) = initialLocation?.position else { return 0 }
        return max(page, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Trang \(currentPage + 1) / \(max(pageCount, 1))").font(.subheadline)
                    .accessibilityLabel("Trang \(currentPage + 1) trên \(pageCount)")
                Spacer()
                Text("PDF").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 8)
            PDFKitReader(url: url, initialPage: initialPage, searchText: searchText, pendingPage: $pendingPage,
                         onPageChange: { page, count in
                let changed = page != currentPage || count != pageCount
                currentPage = page
                pageCount = count
                if changed {
                    let progress = count <= 1 ? (page == 0 ? 0 : 1) : Double(page) / Double(count - 1)
                    onPageChange(page, progress)
                }
            }, onSearchResults: { results, searchable in
                searchResults = results
                canSearch = searchable
                selectedSearchResult = 0
                if !searchText.isEmpty, let first = results.first {
                    NotificationCenter.default.post(name: .pdfReaderGoToSelection, object: first)
                }
            }, onOutline: { outline = $0 })
        }
        .navigationTitle(url.deletingPathExtension().lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showingSearch = true } label: { Label("Tìm", systemImage: "magnifyingglass") }
                    .accessibilityLabel("Tìm trong PDF")
                    .accessibilityIdentifier("pdf-search-button")
                Menu {
                    Button {
                        onBookmark(ReadingLocation(position: .pdf(page: currentPage, anchorX: nil, anchorY: nil)), "Trang \(currentPage + 1)")
                    } label: { Label("Đánh dấu trang \(currentPage + 1)", systemImage: "bookmark") }
                    Button { showBookmarks = true } label: { Label("Dấu trang", systemImage: "bookmarks") }
                    if !outline.isEmpty {
                        Menu("Nội dung") { ForEach(outline) { entry in Button(entry.title) { navigate(to: entry.page) } } }
                    }
                    if !searchResults.isEmpty {
                        Button { moveSearchResult(-1) } label: { Label("Kết quả trước", systemImage: "chevron.up") }
                        Button { moveSearchResult(1) } label: { Label("Kết quả tiếp", systemImage: "chevron.down") }
                    }
                } label: { Label("Công cụ PDF", systemImage: "ellipsis.circle") }
                    .accessibilityLabel("Dấu trang và nội dung PDF")
            }
        }
        .sheet(isPresented: $showBookmarks) { bookmarkSheet }
        .sheet(isPresented: $showingSearch) {
            PDFSearchView(text: $searchText, results: searchResults, canSearch: canSearch) { index in
                guard searchResults.indices.contains(index) else { return }
                selectedSearchResult = index
                NotificationCenter.default.post(name: .pdfReaderGoToSelection, object: searchResults[index])
                showingSearch = false
            }
        }
    }

    private var bookmarkSheet: some View {
        NavigationView {
            List {
                if bookmarks.isEmpty { Text("Chưa có dấu trang.").foregroundColor(.secondary) }
                ForEach(bookmarks) { bookmark in
                    Button(bookmark.title) {
                        if let location = decodeLocation(bookmark.locatorJSON), case let .pdf(page, _, _) = location.position { navigate(to: page) }
                        showBookmarks = false
                    }
                }
            }
            .navigationTitle("Dấu trang")
            .navigationBarItems(trailing: Button("Đóng") { showBookmarks = false })
        }
    }

    private func navigate(to page: Int) {
        pendingPage = min(max(page, 0), max(pageCount - 1, 0))
    }

    private func moveSearchResult(_ delta: Int) {
        guard !searchResults.isEmpty else { return }
        selectedSearchResult = (selectedSearchResult + delta + searchResults.count) % searchResults.count
        NotificationCenter.default.post(name: .pdfReaderGoToSelection, object: searchResults[selectedSearchResult])
    }
    private func decodeLocation(_ json: String) -> ReadingLocation? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadingLocation.self, from: data)
    }
}

private struct PDFSearchView: View {
    @Binding var text: String
    let results: [PDFSelection]
    let canSearch: Bool
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                TextField("Từ khóa", text: $text)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("pdf-search-field")
                if !canSearch {
                    Text("PDF này không có lớp văn bản để tìm kiếm.").foregroundColor(.secondary)
                } else if text.isEmpty {
                    Text("Nhập từ khóa để tìm trong PDF.").foregroundColor(.secondary)
                } else if results.isEmpty {
                    Text("Không tìm thấy kết quả.").foregroundColor(.secondary)
                } else {
                    ForEach(results.indices, id: \.self) { index in
                        Button {
                            onSelect(index)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Kết quả \(index + 1)")
                                if let match = results[index].string, !match.isEmpty {
                                    Text(match).font(.subheadline).foregroundColor(.secondary).lineLimit(3)
                                }
                            }
                        }
                        .accessibilityLabel("Kết quả \(index + 1): \(results[index].string ?? "")")
                        .accessibilityIdentifier("pdf-search-result-\(index)")
                    }
                }
            }
            .navigationTitle("Tìm trong PDF")
            .navigationBarItems(trailing: Button("Đóng") { dismiss() })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

private extension Notification.Name { static let pdfReaderGoToSelection = Notification.Name("pdfReaderGoToSelection") }

private struct PDFKitReader: UIViewRepresentable {
    let url: URL
    let initialPage: Int
    let searchText: String
    @Binding var pendingPage: Int?
    let onPageChange: (Int, Int) -> Void
    let onSearchResults: ([PDFSelection], Bool) -> Void
    let onOutline: ([PDFOutlineEntry]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageChange: onPageChange, onSearchResults: onSearchResults, onOutline: onOutline) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.accessibilityIdentifier = "pdf-document-view"
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false, withViewOptions: nil)
        view.backgroundColor = UIColor.secondarySystemBackground
        view.delegate = context.coordinator
        view.document = PDFDocument(url: url)
        context.coordinator.pdfView = view
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.goToSelection(_:)), name: .pdfReaderGoToSelection, object: nil)
        context.coordinator.updateDocument()
        DispatchQueue.main.async { [weak view] in
            guard let view, let page = view.document?.page(at: max(initialPage, 0)) else { return }
            view.go(to: page)
        }
        return view
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            context.coordinator.updateDocument()
        }
        context.coordinator.search(searchText)
        guard let pageIndex = pendingPage else { return }
        if let page = view.document?.page(at: max(pageIndex, 0)) { view.go(to: page) }
        DispatchQueue.main.async { pendingPage = nil }
    }

    final class Coordinator: NSObject, PDFViewDelegate {
        weak var pdfView: PDFView?
        let onPageChange: (Int, Int) -> Void
        let onSearchResults: ([PDFSelection], Bool) -> Void
        let onOutline: ([PDFOutlineEntry]) -> Void
        private var activeQuery: String?
        private var searchable: Bool?

        init(onPageChange: @escaping (Int, Int) -> Void, onSearchResults: @escaping ([PDFSelection], Bool) -> Void, onOutline: @escaping ([PDFOutlineEntry]) -> Void) {
            self.onPageChange = onPageChange
            self.onSearchResults = onSearchResults
            self.onOutline = onOutline
        }

        func updateDocument() {
            guard let document = pdfView?.document else { return }
            let hasText = !(document.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            searchable = hasText
            activeQuery = nil
            onSearchResults([], hasText)
            onOutline(Self.outlineEntries(document.outlineRoot, document: document))
            if let page = pdfView?.currentPage { onPageChange(document.index(for: page), document.pageCount) }
        }

        func search(_ query: String) {
            guard query != activeQuery else { return }
            activeQuery = query
            guard !query.isEmpty, let document = pdfView?.document, let searchable, searchable else {
                onSearchResults([], searchable ?? false)
                return
            }
            let results = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive]) ?? []
            onSearchResults(results, true)
            if let first = results.first { pdfView?.setCurrentSelection(first, animate: true); pdfView?.go(to: first) }
        }

        @objc func goToSelection(_ notification: Notification) {
            guard let selection = notification.object as? PDFSelection else { return }
            pdfView?.setCurrentSelection(selection, animate: true)
            pdfView?.go(to: selection)
        }
        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let page = view.currentPage, let document = view.document else { return }
            onPageChange(document.index(for: page), document.pageCount)
        }
        private static func outlineEntries(_ root: PDFOutline?, document: PDFDocument) -> [PDFOutlineEntry] {
            guard let root else { return [] }
            var entries: [PDFOutlineEntry] = []
            func visit(_ node: PDFOutline, path: String) {
                for index in 0..<node.numberOfChildren {
                    guard let child = node.child(at: index) else { continue }
                    if let title = child.label, let page = child.destination?.page {
                        entries.append(PDFOutlineEntry(id: "\(path).\(index)", title: title, page: document.index(for: page)))
                    }
                    visit(child, path: "\(path).\(index)")
                }
            }
            visit(root, path: "root")
            return entries
        }
    }
}
