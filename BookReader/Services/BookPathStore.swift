import Foundation
import CryptoKit

struct BookPathStore {
    let rootURL: URL
    let stagingURL: URL
    let booksURL: URL

    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try self.init(rootURL: support.appendingPathComponent("BookReader", isDirectory: true), fileManager: fileManager)
    }

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL.standardizedFileURL
        stagingURL = self.rootURL.appendingPathComponent("Staging", isDirectory: true)
        booksURL = self.rootURL.appendingPathComponent("Books", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: booksURL, withIntermediateDirectories: true)
    }

    func newStagingURL(id: UUID = UUID()) -> URL { stagingURL.appendingPathComponent("\(id.uuidString).partial") }
    func bookURL(id: UUID, format: BookFormat) -> URL {
        booksURL.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("original.\(format.fileExtension)")
    }
    func relativePath(forBookID id: UUID, format: BookFormat) -> String { "Books/\(id.uuidString)/original.\(format.fileExtension)" }

    func resolve(relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains(":"), !relativePath.contains("\\"),
              !relativePath.split(separator: "/").contains(".."), !relativePath.split(separator: "/").contains(".") else { throw ImportFailure.invalid }
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let resolved = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard resolved.path.hasPrefix(rootPath) else { throw ImportFailure.invalid }
        var cursor = rootURL
        for component in relativePath.split(separator: "/") {
            cursor.appendPathComponent(String(component))
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: cursor.path) else { continue }
            if let type = attributes[.type] as? FileAttributeType, type == .typeSymbolicLink { throw ImportFailure.invalid }
        }
        return resolved
    }

    func sha256(of url: URL, chunkSize: Int = 1_048_576) throws -> String {
        guard chunkSize > 0 else { throw ImportFailure.invalid }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw ImportFailure.io }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: chunkSize), !data.isEmpty { hasher.update(data: data) }
        } catch { throw ImportFailure.io }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
