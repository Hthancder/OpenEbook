import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var sortOption = LibrarySortOption.recent
    @State private var selectedBook: BookRecord?
    @State private var bookToDelete: BookRecord?

    private var filteredBooks: [BookRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = model.books.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.author?.localizedCaseInsensitiveContains(query) ?? false) }
        switch sortOption {
        case .recent: return matching.sorted { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
        case .title: return matching.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .added: return matching.sorted { $0.addedAt > $1.addedAt }
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if model.books.isEmpty { emptyState }
                else if filteredBooks.isEmpty { noResultsState }
                else { bookList }
            }
            .navigationTitle("Thư viện")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingImporter = true }) { Label("Nhập sách", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("import-book")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSearch = true }) { Label("Tìm", systemImage: "magnifyingglass") }
                        .accessibilityIdentifier("search-books")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sắp xếp", selection: $sortOption) {
                            ForEach(LibrarySortOption.allCases) { option in Text(option.label).tag(option) }
                        }
                    } label: { Label("Sắp xếp", systemImage: "arrow.up.arrow.down") }.accessibilityLabel("Sắp xếp sách")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) { Label("Cài đặt", systemImage: "gearshape") }
                        .accessibilityIdentifier("settings")
                }
            }
        }
        .sheet(isPresented: $showingSearch) { LibrarySearchView(text: $searchText) }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: BookTypeRegistry.supported, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importFiles(urls)
            case .failure(let error as CocoaError) where error.code == .userCancelled: break
            case .failure: model.importMessage = "Không thể mở bộ chọn tệp."
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
        .fullScreenCover(item: $selectedBook) { book in
            NavigationView { ReaderHostView(book: book, model: model) }
                .navigationViewStyle(StackNavigationViewStyle())
        }
        .alert("Xóa sách?", isPresented: Binding(get: { bookToDelete != nil }, set: { if !$0 { bookToDelete = nil } })) {
            Button("Xóa", role: .destructive) {
                guard let book = bookToDelete else { return }
                do { try model.delete(book) }
                catch { model.importMessage = "Không thể xóa sách; bản ghi và bản sao được giữ để thử lại." }
                bookToDelete = nil
            }
            Button("Hủy", role: .cancel) { bookToDelete = nil }
        } message: { Text(bookToDelete?.title ?? "") }
        .alert("Thông báo", isPresented: Binding(
            get: { model.importMessage != nil },
            set: { if !$0 { model.importMessage = nil } }
        )) {
            Button("Đóng", role: .cancel) { model.importMessage = nil }
        } message: { Text(model.importMessage ?? "") }
    }


    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical").font(.system(size: 54)).foregroundColor(.accentColor).accessibilityHidden(true)
            Text("Chưa có sách").font(.title2.weight(.semibold))
            Text("Nhập EPUB, PDF hoặc TXT để bắt đầu đọc offline.").multilineTextAlignment(.center).foregroundColor(.secondary)
            Button("Nhập sách") { showingImporter = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("empty-import-book")
        }.padding(32)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundColor(.secondary)
            Text("Không tìm thấy sách").font(.headline)
            Button("Xóa tìm kiếm") { searchText = "" }
        }.padding(32)
    }

    private var bookList: some View {
        List {
            if let reading = filteredBooks.first(where: { $0.lastOpenedAt != nil }) {
                Section(header: Text("Đọc tiếp")) { BookCardView(book: reading, coverImage: model.coverImage(for: reading)) { selectedBook = reading } }
            }
            Section(header: Text("Sách của bạn")) {
                ForEach(filteredBooks) { book in
                    BookCardView(book: book, coverImage: model.coverImage(for: book)) { selectedBook = book }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { bookToDelete = book } label: { Label("Xóa", systemImage: "trash") }
                                .accessibilityLabel("Xóa \(book.title)")
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.isImporting {
                VStack(spacing: 10) {
                    ProgressView(value: Double(model.importCompleted), total: Double(max(model.importTotal, 1)))
                    Text("Đang nhập \(model.importCompleted)/\(model.importTotal) tệp")
                        .accessibilityIdentifier("import-progress")
                    Button("Hủy nhập", role: .cancel) { model.cancelImport() }
                }.padding(16).background(.regularMaterial).cornerRadius(12)
            }
        }
    }
}

private struct LibrarySearchView: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                TextField("Tên hoặc tác giả", text: $text)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("library-search-field")
            }
            .navigationTitle("Tìm sách")
            .navigationBarItems(trailing: Button("Đóng") { dismiss() })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
