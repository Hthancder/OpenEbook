import SwiftUI

struct ReaderHostView: View {
    let book: BookRecord
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete = false

    var body: some View {
        Group {
            switch book.format {
            case .pdf:
                if let url = model.fileURL(for: book) {
                    PDFReaderView(url: url, initialLocation: decodeLocation(book.locatorJSON), bookmarks: decodeBookmarks(book.bookmarkJSON), onPageChange: { page, progress in
                        let location = ReadingLocation(position: .pdf(page: page, anchorX: nil, anchorY: nil))
                        model.saveLocation(location, progress: progress, for: book)
                    }, onBookmark: { location, title in model.addBookmark(location, title: title, for: book) })
                } else { missingFileView }
            case .txt:
                if let url = model.fileURL(for: book) {
                    TextReaderView(url: url, initialLocation: decodeLocation(book.locatorJSON), bookmarks: decodeBookmarks(book.bookmarkJSON), textSize: model.textSize, onLocation: { location, progress in
                        model.saveLocation(location, progress: progress, for: book)
                    }, onBookmark: { location, title in model.addBookmark(location, title: title, for: book) })
                        .background(textBackground)
                } else { missingFileView }
            case .epub:
                VStack(spacing: 14) {
                    Image(systemName: "network.slash").font(.largeTitle).foregroundColor(.orange)
                    Text("Đã tạm khóa đọc EPUB trực tiếp").font(.headline)
                    Text("Bản Readium đang dùng chưa chứng minh được rằng mọi yêu cầu mạng bị chặn trước lần tải đầu. Sách EPUB được giữ lại nhưng chưa thể mở an toàn.")
                        .multilineTextAlignment(.center).foregroundColor(.secondary)
                    Text("Việc nhập và giữ sách EPUB không làm thay đổi PDF, TXT hay tệp nguồn.")
                        .multilineTextAlignment(.center).foregroundColor(.secondary)
                    Button("Đóng") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding(24)
            }
        }
        .onAppear { model.markOpened(book) }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Xóa khỏi thư viện", role: .destructive) { pendingDelete = true }
                    Button("Đóng") { dismiss() }
                } label: { Label("Tùy chọn sách", systemImage: "ellipsis.circle") }
            }
        }
        .alert("Xóa sách?", isPresented: $pendingDelete) {
            Button("Xóa", role: .destructive) {
                do { try model.delete(book); dismiss() }
                catch { model.importMessage = "Không thể xóa sách; bản sao và bản ghi vẫn được giữ." }
            }
            Button("Hủy", role: .cancel) {}
        }
    }

    private var textBackground: Color {
        switch model.textBackgroundName { case "dark": return Color.black; case "light": return Color.white; default: return Color(red: 0.98, green: 0.96, blue: 0.90) }
    }

    private var missingFileView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.exclamationmark").font(.largeTitle).foregroundColor(.orange)
            Text("Không tìm thấy bản sao sách").font(.headline)
            Text("Bản ghi thư viện vẫn được giữ để phục hồi hoặc thử lại.").multilineTextAlignment(.center).foregroundColor(.secondary)
        }
        .padding(24)
    }

    private func decodeLocation(_ json: String?) -> ReadingLocation? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadingLocation.self, from: data)
    }

    private func decodeBookmarks(_ json: String?) -> [ReaderBookmark] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ReaderBookmark].self, from: data)) ?? []
    }
}
