import Foundation
import PDFKit
import XCTest
@testable import BookReader

final class FoundationTests: XCTestCase {
    func testTextImportRemainsOfflineDurableAndDuplicateReturnsExistingRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try BookPathStore(rootURL: root.appendingPathComponent("ApplicationSupport"))
        let library = try PersistentLibraryStore(inMemory: true)
        let importer = ImportService(paths: paths, library: library)
        let source = root.appendingPathComponent("reading.txt")
        try Data("Vietnamese text".utf8).write(to: source)
        let result = await importer.importFile(from: source)
        let record = try XCTUnwrap(result.record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try paths.resolve(relativePath: record.relativePath).path))
        let duplicate = await importer.importFile(from: source)
        XCTAssertEqual(duplicate.failure, .duplicate(existingID: record.id))
        XCTAssertEqual(library.allBooks().map(\.id), [record.id])
    }

    func testEPUBImportIsRejectedWithoutCreatingLibraryOrStagingData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try BookPathStore(rootURL: root.appendingPathComponent("ApplicationSupport"))
        let library = try PersistentLibraryStore(inMemory: true)
        let importer = ImportService(paths: paths, library: library)
        let source = root.appendingPathComponent("unsafe-first-load.epub")
        try Data("not an EPUB archive".utf8).write(to: source)
        let result = await importer.importFile(from: source)
        XCTAssertEqual(result.failure, .invalid)

        XCTAssertTrue(library.allBooks().isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.stagingURL.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCatalogPersistsReadingPositionProgressAndBookmarks() throws {
        let store = try PersistentLibraryStore(inMemory: true)
        let id = UUID()
        try store.add(BookRecord(id: id, relativePath: "Books/\(id.uuidString)/original.txt", format: .txt, title: "Thử", fileSize: 5, sha256: "abc123"))
        let location = ReadingLocation(position: .text(offset: 3, normalizationVersion: 1))
        try store.updateLocation(id: id, location: location)
        try store.updateProgress(id: id, progress: 0.6)
        let bookmark = ReaderBookmark(locatorJSON: String(decoding: try JSONEncoder().encode(location), as: UTF8.self), title: "Dòng 4")
        try store.updateBookmarks(id: id, bookmarksJSON: String(decoding: try JSONEncoder().encode([bookmark]), as: UTF8.self))
        let loaded = try XCTUnwrap(store.book(id: id))
        let storedLocation = try JSONDecoder().decode(ReadingLocation.self, from: Data(try XCTUnwrap(loaded.locatorJSON).utf8))
        XCTAssertEqual(storedLocation, location)
        XCTAssertEqual(loaded.progress, 0.6, accuracy: 0.0001)
        XCTAssertEqual(try JSONDecoder().decode([ReaderBookmark].self, from: Data(try XCTUnwrap(loaded.bookmarkJSON).utf8)), [bookmark])
    }

    func testEncryptedPDFIsRejectedBeforeCatalogCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try BookPathStore(rootURL: root.appendingPathComponent("ApplicationSupport"))
        let library = try PersistentLibraryStore(inMemory: true)
        let importer = ImportService(paths: paths, library: library)
        let source = root.appendingPathComponent("secret.pdf")
        let bytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { $0.beginPage() }
        let document = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertTrue(document.write(to: source, withOptions: [.ownerPasswordOption: "test", .userPasswordOption: "test"]))
        let result = await importer.importFile(from: source)
        XCTAssertEqual(result.failure, .protected)
        XCTAssertTrue(library.allBooks().isEmpty)
    }
}
