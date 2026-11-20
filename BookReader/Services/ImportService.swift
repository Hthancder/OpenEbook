import Foundation
import CryptoKit
import PDFKit

struct ImportService {
    static let maximumFileSize: Int64 = 250 * 1024 * 1024
    static let maximumTextFileSize = TextDecoder.maximumTextFileSize
    let paths: BookPathStore
    let library: LibraryStore
    let fileManager: FileManager
    let pdfOpener: PDFDocumentOpening

    init(paths: BookPathStore, library: LibraryStore, fileManager: FileManager = .default, pdfOpener: PDFDocumentOpening = PDFDocumentOpening()) {
        self.paths = paths; self.library = library; self.fileManager = fileManager; self.pdfOpener = pdfOpener
    }

    func importFile(from sourceURL: URL) async -> ImportResult {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let format = BookFormatRegistry.format(forPathExtension: sourceURL.pathExtension) else { return failure(sourceURL, .unsupported) }
        let resourceValues: URLResourceValues
        do { resourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) }
        catch { return failure(sourceURL, .io) }
        guard resourceValues.isRegularFile == true, let sourceSize = resourceValues.fileSize, sourceSize > 0 else { return failure(sourceURL, .invalid) }
        let sizeLimit = format == .txt ? Self.maximumTextFileSize : Self.maximumFileSize
        guard Int64(sourceSize) <= sizeLimit else { return failure(sourceURL, .tooLarge) }

        let id = UUID()
        let staging = paths.newStagingURL(id: id)
        let bookDirectory = paths.booksURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let destination = paths.bookURL(id: id, format: format)
        do {
            try copy(sourceURL: sourceURL, destinationURL: staging, maximumBytes: sizeLimit)
            let digest = try paths.sha256(of: staging)
            if let existing = library.allBooks().first(where: { $0.sha256 == digest }) {
                try? fileManager.removeItem(at: staging)
                return failure(sourceURL, .duplicate(existingID: existing.id))
            }

            let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent
            var metadata = EPUBMetadata(title: fallbackTitle.isEmpty ? "Sách chưa có tên" : fallbackTitle, author: nil, coverPath: nil)
            switch format {
            case .txt:
                try Self.validateText(at: staging)
            case .pdf:
                if pdfOpener.isPasswordProtected(at: staging) { throw ImportFailure.protected }
                guard let pageCount = pdfOpener.pageCount(at: staging), pageCount > 0 else { throw ImportFailure.invalid }
            case .epub:
                try await EPUBArchivePreflight.validate(url: staging)
                metadata = try await EPUBMetadataReader.read(url: staging, fallbackTitle: metadata.title)
                throw ImportFailure.networkPolicy
            }

            let record = BookRecord(id: id, relativePath: paths.relativePath(forBookID: id, format: format), format: format,
                                    title: metadata.title, author: metadata.author, fileSize: Int64(sourceSize), sha256: digest,
                                    coverPath: metadata.coverPath)
            try fileManager.createDirectory(at: bookDirectory, withIntermediateDirectories: false)
            try fileManager.moveItem(at: staging, to: destination)
            do { try library.add(record) }
            catch { try? fileManager.removeItem(at: bookDirectory); throw error }
            return ImportResult(sourceURL: sourceURL, record: record, failure: nil)
        } catch let failure as ImportFailure {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: bookDirectory)
            return ImportResult(sourceURL: sourceURL, record: nil, failure: failure)
        } catch {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: bookDirectory)
            return failure(sourceURL, .io)
        }
    }

    private func copy(sourceURL: URL, destinationURL: URL, maximumBytes: Int64) throws {
        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard !fileManager.fileExists(atPath: destinationURL.path), fileManager.createFile(atPath: destinationURL.path, contents: nil) else { throw ImportFailure.io }
            let input = try FileHandle(forReadingFrom: sourceURL)
            let output = try FileHandle(forWritingTo: destinationURL)
            defer { try? input.close(); try? output.close() }
            var byteCount: Int64 = 0
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                let (nextCount, overflow) = byteCount.addingReportingOverflow(Int64(chunk.count))
                guard !overflow, nextCount <= maximumBytes else { throw ImportFailure.tooLarge }
                byteCount = nextCount
                try output.write(contentsOf: chunk)
            }
            guard byteCount > 0 else { throw ImportFailure.invalid }
            try output.synchronize()
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if let failure = error as? ImportFailure { throw failure }
            throw ImportFailure.io
        }
    }

    private static func validateText(at url: URL) throws {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw ImportFailure.io }
        _ = try TextDecoder.decode(data: data)
    }

    private func failure(_ sourceURL: URL, _ error: ImportFailure) -> ImportResult {
        ImportResult(sourceURL: sourceURL, record: nil, failure: error)
    }
}
