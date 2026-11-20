import UIKit
import SwiftUI
import ReadiumNavigator

struct EPUBReaderView: View {
    let book: BookRecord
    let url: URL
    @ObservedObject var model: AppModel
    @StateObject private var navigation = EPUBNavigationModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingBookmarks = false
    @State private var showingSearch = false
    @State private var searchQuery = ""

    var body: some View {
        Group {
            if let error = navigation.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "book.closed").font(.largeTitle).foregroundColor(.secondary)
                    Text("Không thể mở EPUB").font(.headline)
                    Text(error).multilineTextAlignment(.center).foregroundColor(.secondary)
                }.padding(24)
            } else if let navigator = navigation.navigator {
                EPUBNavigatorContainer(controller: navigator)
            } else {
                ProgressView("Đang mở EPUB…")
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if navigation.isSearchable {
                    Button { showingSearch = true } label: { Label("Tìm", systemImage: "magnifyingglass") }
                        .accessibilityLabel("Tìm trong EPUB")
                }
                Menu {
                    if !navigation.contents.isEmpty { Button("Mục lục", systemImage: "list.bullet") { showingContents = true } }
                    Button("Đánh dấu vị trí", systemImage: "bookmark") { navigation.addCurrentBookmark(for: book, model: model) }
                    Button("Dấu trang", systemImage: "bookmarks") { navigation.showBookmarks(for: book, model: model); showingBookmarks = true }
                    if navigation.isReflowable {
                        Slider(value: $navigation.fontSize, in: 14...30, step: 1).accessibilityLabel("Cỡ chữ EPUB")
                        Slider(value: $navigation.lineSpacing, in: 1...1.8, step: 0.1).accessibilityLabel("Giãn dòng EPUB")
                        Picker("Nền đọc", selection: $navigation.backgroundName) {
                            Text("Giấy").tag("paper")
                            Text("Sáng").tag("light")
                            Text("Tối").tag("dark")
                        }
                    }
                } label: { Label("Công cụ đọc", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showingContents) { contentsSheet }
        .sheet(isPresented: $showingBookmarks) { bookmarksSheet }
        .sheet(isPresented: $showingSearch) {
            EPUBSearchView(text: $searchQuery, onSubmit: { navigation.search(searchQuery) })
        }
        .alert("Thông báo EPUB", isPresented: Binding(get: { navigation.searchMessage != nil }, set: { if !$0 { navigation.searchMessage = nil } })) {
            Button("Đóng", role: .cancel) { navigation.searchMessage = nil }
        }
        .onAppear {
            guard navigation.navigator == nil, navigation.errorMessage == nil else { return }
            navigation.open(url: url, initialLocatorJSON: navigation.initialLocatorJSON(for: book), textSize: model.textSize, model: model, book: book)
        }
    }

    private var contentsSheet: some View {
        NavigationView {
            List { contents(navigation.contents) }
                .navigationTitle("Mục lục")
                .navigationBarItems(trailing: Button("Đóng") { showingContents = false })
        }
    }

    private func contents(_ links: [ReadiumShared.Link], depth: Int = 0) -> [AnyView] {
        links.flatMap { link -> [AnyView] in
            let row = AnyView(Button {
                navigation.navigate(to: link)
                showingContents = false
            } label: {
                Text(link.title ?? link.href)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.leading, CGFloat(depth * 16))
            })
            return [row] + contents(link.children, depth: depth + 1)
        }
    }

    private var bookmarksSheet: some View {
        NavigationView {
            Group {
                if navigation.bookmarks.isEmpty {
                    Text("Chưa có dấu trang.").foregroundColor(.secondary)
                } else {
                    List(navigation.bookmarks) { bookmark in
                        Button(bookmark.title) {
                            navigation.navigate(to: bookmark)
                            showingBookmarks = false
                        }
                    }
                }
            }
            .navigationTitle("Dấu trang")
            .navigationBarItems(trailing: Button("Đóng") { showingBookmarks = false })
        }
    }
}

private struct EPUBNavigatorContainer: UIViewControllerRepresentable {
    let controller: EPUBNavigatorViewController
    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { controller }
    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {}
}

private struct EPUBSearchView: View {
    @Binding var text: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                TextField("Từ khóa", text: $text)
                    .accessibilityIdentifier("epub-search-field")
                Button("Tìm") {
                    onSubmit()
                    dismiss()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Tìm trong EPUB")
            .navigationBarItems(trailing: Button("Đóng") { dismiss() })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
