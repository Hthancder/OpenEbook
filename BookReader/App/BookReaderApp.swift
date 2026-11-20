import Foundation
import SwiftUI
import UIKit

@main
struct BookReaderApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene { WindowGroup { LibraryView(model: model).preferredColorScheme(model.colorScheme) } }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var books: [BookRecord] = []
    @Published var importMessage: String?
    @Published var isImporting = false
    @Published var importCompleted = 0
    @Published var importTotal = 0
    @Published var colorScheme: ColorScheme?
    @Published var textSize: Double
    @Published var textBackgroundName: String
    let library: LibraryStore
    let paths: BookPathStore?
    let importer: ImportService?
    private var importTask: Task<Void, Never>?

    init() {
        textSize = UserDefaults.standard.object(forKey: "reader.textSize") as? Double ?? 18
        textBackgroundName = UserDefaults.standard.string(forKey: "reader.textBackground") ?? "paper"
        do {
            let uiTesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
            let paths = try BookPathStore()
            let library = try PersistentLibraryStore(inMemory: uiTesting)
            self.paths = paths
            self.library = library
            self.importer = ImportService(paths: paths, library: library)
            reload()
            if !uiTesting && !LibraryRecovery.inspect(paths: paths, records: books).isEmpty {
                importMessage = "Thư viện cần kiểm tra các tệp chưa hoàn tất. Dữ liệu chưa bị xóa."
            }
        } catch {
            self.library = (try? PersistentLibraryStore(inMemory: true)) ?? UnavailableLibraryStore()
            self.paths = nil
            self.importer = nil
            importMessage = "Không thể khởi tạo thư viện sách. Dữ liệu cũ chưa bị xóa."
        }
    }

    func reload() { books = library.allBooks() }
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        guard let importer else { importMessage = "Thư viện chưa sẵn sàng."; return }
        isImporting = true; importCompleted = 0; importTotal = urls.count; importMessage = nil
        importTask = Task { [weak self] in
            var failures: [String] = []
            var added = 0
            for url in urls {
                guard !Task.isCancelled else { break }
                let result = await importer.importFile(from: url)
                guard let self else { return }
                self.importCompleted += 1
                if let failure = result.failure {
                    if case .duplicate(let id) = failure, let existing = self.library.book(id: id) {
                        failures.append("\(url.lastPathComponent): Đã có ‘\(existing.title)’ trong thư viện.")
                    } else { failures.append("\(url.lastPathComponent): \(failure.message)") }
                } else { added += 1 }
                self.reload()
            }
            guard let self else { return }
            let cancelled = Task.isCancelled
            self.isImporting = false; self.importTask = nil
            let summary = "Đã thêm \(added) sách." + (failures.isEmpty ? "" : "\n" + failures.joined(separator: "\n"))
            self.importMessage = cancelled ? "Đã hủy sau \(self.importCompleted)/\(self.importTotal) tệp.\n\(summary)" : summary
        }
    }
    func cancelImport() { importTask?.cancel() }

    func fileURL(for book: BookRecord) -> URL? {
        guard let paths, let file = try? paths.resolve(relativePath: book.relativePath), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    func coverImage(for book: BookRecord) -> UIImage? {
        guard let relativePath = book.coverPath, let paths,
              let url = try? paths.resolve(relativePath: relativePath),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func markOpened(_ book: BookRecord) {
        do { try library.updateLastOpened(id: book.id, at: Date()); reload() }
        catch { importMessage = "Không thể ghi nhận lần mở sách này." }
    }

    func delete(_ book: BookRecord) throws {
        guard let paths, let url = try? paths.resolve(relativePath: book.relativePath) else { throw ImportFailure.invalid }
        let directory = url.deletingLastPathComponent()
        let quarantine = directory.appendingPathExtension("deleting")
        guard FileManager.default.fileExists(atPath: directory.path), !FileManager.default.fileExists(atPath: quarantine.path) else { throw ImportFailure.io }
        try FileManager.default.moveItem(at: directory, to: quarantine)
        do { try library.remove(id: book.id) }
        catch { try? FileManager.default.moveItem(at: quarantine, to: directory); throw error }
        reload()
        do { try FileManager.default.removeItem(at: quarantine) }
        catch { importMessage = "Sách đã bị xóa khỏi thư viện, nhưng bản sao tạm còn sót lại." }
    }

    func saveLocation(_ location: ReadingLocation, progress: Double? = nil, for book: BookRecord) {
        do {
            try library.updateLocation(id: book.id, location: location)
            try library.updateLastOpened(id: book.id, at: Date())
            if let progress { try library.updateProgress(id: book.id, progress: progress) }
            reload()
        } catch { importMessage = "Không thể lưu vị trí đọc mới." }
    }

    func addBookmark(_ location: ReadingLocation, title: String, for book: BookRecord) {
        do {
            let stored = library.book(id: book.id)?.bookmarkJSON
            let existing = stored.flatMap { try? JSONDecoder().decode([ReaderBookmark].self, from: Data($0.utf8)) } ?? []
            let locator = String(decoding: try JSONEncoder().encode(location), as: UTF8.self)
            let bookmarks = existing + [ReaderBookmark(locatorJSON: locator, title: title)]
            try library.updateBookmarks(id: book.id, bookmarksJSON: String(decoding: try JSONEncoder().encode(bookmarks), as: UTF8.self))
            reload()
            importMessage = "Đã thêm dấu trang."
        } catch { importMessage = "Không thể lưu dấu trang." }
    }
}
