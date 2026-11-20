import Foundation
import SwiftSoup
import ReadiumZIPFoundation

struct EPUBMetadataReader {
    static func read(url: URL, fallbackTitle: String) async throws -> EPUBMetadata {
        let archive: Archive
        do { archive = try await Archive(url: url, accessMode: .read) } catch { throw ImportFailure.invalid }
        guard let containerEntry = try await archive.get("META-INF/container.xml") else { throw ImportFailure.invalid }
        let containerData = try await read(containerEntry, from: archive, maximum: EPUBArchivePreflight.maximumContainerBytes)
        let containerText = try safeXMLText(containerData)
        let container = try SwiftSoup.parseXML(containerData)
        guard let rootfile = try container.select("rootfile[full-path]").first() else { throw ImportFailure.invalid }
        let packagePath = try rootfile.attr("full-path")
        guard ImportSecurity.validateArchivePath(packagePath), let packageEntry = try await archive.get(packagePath) else { throw ImportFailure.invalid }
        let packageData = try await read(packageEntry, from: archive, maximum: EPUBArchivePreflight.maximumPackageBytes)
        return try parse(containerText: containerText, packageData: packageData, packagePath: packagePath, fallbackTitle: fallbackTitle)
    }

    private static func parse(containerText: String, packageData: Data, packagePath: String, fallbackTitle: String) throws -> EPUBMetadata {
        let container = try SwiftSoup.parseXML(Data(containerText.utf8))
        guard let rootfile = try container.select("rootfile[full-path]").first(), try rootfile.attr("full-path") == packagePath else { throw ImportFailure.invalid }
        let packageText = try safeXMLText(packageData)
        let package = try SwiftSoup.parseXML(Data(packageText.utf8))
        guard try package.tagName().lowercased() == "package", let metadata = try package.select("metadata").first() else { throw ImportFailure.invalid }
        let rawTitle = try metadata.select("title").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
        guard !title.isEmpty else { throw ImportFailure.invalid }
        let rawAuthor = try metadata.select("creator").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
        let author = rawAuthor.flatMap { $0.isEmpty ? nil : $0 }
        let cover = try package.select("manifest item[properties~=cover-image]").first()?.attr("href")
        return EPUBMetadata(title: title, author: author, coverPath: cover.flatMap { relativePath($0, from: packagePath) })
    }

    private static func read(_ entry: Entry, from archive: Archive, maximum: Int) async throws -> Data {
        guard maximum >= 0, entry.type == .file, entry.uncompressedSize <= UInt64(maximum) else { throw ImportFailure.archiveUnsafe }
        let accumulator = EPUBDataAccumulator(maximumBytes: maximum)
        try await archive.extract(entry, bufferSize: 8192) { chunk in try await accumulator.append(chunk) }
        return await accumulator.value()
    }

    private static func safeXMLText(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8), !EPUBArchivePreflight.containsExternalEntityDeclaration(text) else { throw ImportFailure.invalid }
        return text
    }

    private static func relativePath(_ href: String, from packagePath: String) -> String? {
        let parent = (packagePath as NSString).deletingLastPathComponent
        var components = parent.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for component in href.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." { guard !components.isEmpty else { return nil }; components.removeLast() }
            else { components.append(String(component)) }
        }
        let path = components.joined(separator: "/")
        return ImportSecurity.validateArchivePath(path) ? path : nil
    }
}
