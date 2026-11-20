import SwiftUI

struct TextReaderView: View {
    let url: URL
    let initialLocation: ReadingLocation?
    let bookmarks: [ReaderBookmark]
    let textSize: Double
    let onLocation: (ReadingLocation, Double) -> Void
    let onBookmark: (ReadingLocation, String) -> Void

    @State private var text: String?
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var searchMatches: [Int] = []
    @State private var showingSearch = false
    @State private var currentLine = 0
    @State private var showBookmarks = false
    @State private var selectedBookmarkLine: Int?
    @State private var hasRestoredPosition = false

    private var lines: [String] { (text ?? "").components(separatedBy: .newlines) }
    private var safeTextSize: Double { textSize.isFinite ? min(max(textSize, 14), 30) : 18 }
    private var initialLine: Int {
        guard case let .text(offset, _) = initialLocation?.position else { return 0 }
        return min(max(offset, 0), max(lines.count - 1, 0))
    }

    var body: some View {
        Group {
            if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.exclamationmark").font(.largeTitle)
                    Text(errorMessage).multilineTextAlignment(.center)
                }.padding(24)
            } else if text != nil {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: safeTextSize, design: .serif))
                                    .lineSpacing(5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(index)
                                    .background(GeometryReader { geometry in
                                        Color.clear.preference(key: TextVisiblePreferenceKey.self,
                                            value: geometry.frame(in: .named("readerScroll")).maxY > 0 ? index : nil)
                                    })
                            }
                        }.padding(.horizontal, 20).padding(.vertical, 12)
                    }
                    .coordinateSpace(name: "readerScroll")
                    .onPreferenceChange(TextVisiblePreferenceKey.self) { value in
                        if hasRestoredPosition, let value {
                            currentLine = min(max(value, 0), max(lines.count - 1, 0))
                            persistPosition(at: currentLine)
                        }
                    }
                    .onAppear {
                        let line = initialLine
                        currentLine = line
                        DispatchQueue.main.async {
                            proxy.scrollTo(line, anchor: .top)
                            DispatchQueue.main.async { hasRestoredPosition = true }
                        }
                    }
                    .onChange(of: searchMatches) { matches in
                        if let first = matches.first { withAnimation { proxy.scrollTo(first, anchor: .center) } }
                    }
                    .onChange(of: selectedBookmarkLine) { value in
                        if let line = value {
                            withAnimation { proxy.scrollTo(line, anchor: .top) }
                            selectedBookmarkLine = nil
                        }
                    }
                    .onDisappear { persistPosition() }
                }
            } else { ProgressView("Đang mở văn bản…") }
        }
        .navigationTitle(url.deletingPathExtension().lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showingSearch = true } label: { Label("Tìm", systemImage: "magnifyingglass") }
                    .accessibilityLabel("Tìm trong văn bản")
                    .accessibilityIdentifier("text-search-button")
                Menu {
                    Button {
                        let location = ReadingLocation(position: .text(offset: currentLine, normalizationVersion: 1))
                        onBookmark(location, "Dòng \(currentLine + 1)")
                    } label: { Label("Đánh dấu dòng \(currentLine + 1)", systemImage: "bookmark") }
                    Button { showBookmarks = true } label: { Label("Dấu trang", systemImage: "bookmarks") }
                } label: { Label("Công cụ đọc", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showingSearch) {
            TextSearchView(text: $searchText, matches: searchMatches, lines: lines) { line in
                selectedBookmarkLine = line
                showingSearch = false
            }
        }
        .onChange(of: searchText) { query in
            searchMatches = query.isEmpty ? [] : lines.indices.filter { lines[$0].localizedCaseInsensitiveContains(query) }
        }
        .sheet(isPresented: $showBookmarks) {
            NavigationView {
                List {
                    if bookmarks.isEmpty { Text("Chưa có dấu trang.").foregroundColor(.secondary) }
                    ForEach(bookmarks) { bookmark in
                        Button(bookmark.title) {
                            if let location = decodeLocation(bookmark.locatorJSON), case let .text(offset, _) = location.position {
                                selectedBookmarkLine = min(max(offset, 0), max(lines.count - 1, 0))
                            }
                            showBookmarks = false
                        }
                    }
                }
                .navigationTitle("Dấu trang")
                .navigationBarItems(trailing: Button("Đóng") { showBookmarks = false })
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        do { text = try TextDecoder.decode(url: url) }
        catch let failure as ImportFailure { errorMessage = failure.message }
        catch { errorMessage = "Không thể mở tệp văn bản." }
    }

    private func decodeLocation(_ json: String) -> ReadingLocation? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadingLocation.self, from: data)
    }

    private func persistPosition(at line: Int? = nil) {
        guard !lines.isEmpty else { return }
        let current = min(max(line ?? currentLine, 0), lines.count - 1)
        let progress = lines.count <= 1 ? 0 : Double(current) / Double(lines.count - 1)
        onLocation(ReadingLocation(position: .text(offset: current, normalizationVersion: 1)), progress)
    }
}

private struct TextVisiblePreferenceKey: PreferenceKey {
    static var defaultValue: Int?
    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        if let next = nextValue() { value = min(value ?? next, next) }
    }
}

private struct TextSearchView: View {
    @Binding var text: String
    let matches: [Int]
    let lines: [String]
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                TextField("Từ khóa", text: $text)
                    .accessibilityIdentifier("text-search-field")
                if text.isEmpty {
                    Text("Nhập từ khóa để tìm trong văn bản.").foregroundColor(.secondary)
                } else if matches.isEmpty {
                    Text("Không tìm thấy kết quả.").foregroundColor(.secondary)
                } else {
                    ForEach(matches, id: \.self) { line in
                        Button("Dòng \(line + 1): \(lines[line])") {
                            onSelect(line)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Tìm trong văn bản")
            .navigationBarItems(trailing: Button("Đóng") { dismiss() })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
