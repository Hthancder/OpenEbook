import Foundation
import SwiftSoup
import ReadiumZIPFoundation

struct EPUBArchivePreflight {
    static let maximumEntries = 10_000
    static let maximumUncompressedBytes: Int64 = 1_073_741_824
    static let maximumEntryBytes: Int64 = 104_857_600
    static let maximumContainerBytes = 64 * 1024
    static let maximumPackageBytes = 4 * 1024 * 1024

    static func validate(url: URL) async throws {
        let archive: Archive
        do { archive = try await Archive(url: url, accessMode: .read) } catch { throw ImportFailure.invalid }
        let entries: [Entry]
        do { entries = try await archive.entries() } catch { throw ImportFailure.invalid }
        guard !entries.isEmpty else { throw ImportFailure.invalid }
        guard entries.count <= maximumEntries else { throw ImportFailure.archiveUnsafe }
        var declaredTotal: Int64 = 0
        var containerFound = false
        let extractionState = EPUBExtractionState()
        for (index, entry) in entries.enumerated() {
            guard index < maximumEntries, ImportSecurity.validateArchivePath(entry.path), entry.type != .symlink,
                  entry.uncompressedSize <= UInt64(maximumEntryBytes), entry.compressedSize <= UInt64(maximumEntryBytes),
                  !entry.isEncrypted, !entry.isCompressed || entry.compressedSize > 0,
                  entry.uncompressedSize <= UInt64(Int64.max) else { throw ImportFailure.archiveUnsafe }
            let declaredEntry = Int64(entry.uncompressedSize)
            let (nextDeclared, declaredOverflow) = declaredTotal.addingReportingOverflow(declaredEntry)
            guard !declaredOverflow, nextDeclared <= maximumUncompressedBytes else { throw ImportFailure.archiveUnsafe }
            declaredTotal = nextDeclared
            if entry.path == "META-INF/container.xml" { containerFound = true }
            await extractionState.beginEntry()
            do {
                try await archive.extract(entry, bufferSize: 16_384) { chunk in
                    try await extractionState.consume(chunk, declaredEntryBytes: declaredEntry, declaredTotalBytes: nextDeclared)
                }
            } catch let failure as ImportFailure { throw failure }
            catch { throw ImportFailure.archiveUnsafe }
            guard await extractionState.entryByteCount() == declaredEntry else { throw ImportFailure.archiveUnsafe }
        }
        guard containerFound, let containerEntry = try await archive.get("META-INF/container.xml") else { throw ImportFailure.invalid }
        let containerData = try await read(containerEntry, from: archive, maximum: maximumContainerBytes)
        guard let containerText = String(data: containerData, encoding: .utf8),
              !containsExternalEntityDeclaration(containerText) else { throw ImportFailure.invalid }
        let container = try SwiftSoup.parseXML(containerData)
        guard let rootfile = try container.select("rootfile[full-path]").first() else { throw ImportFailure.invalid }
        let packagePath = try rootfile.attr("full-path")
        guard ImportSecurity.validateArchivePath(packagePath), let packageEntry = try await archive.get(packagePath) else { throw ImportFailure.invalid }
        let packageData = try await read(packageEntry, from: archive, maximum: maximumPackageBytes)
        guard let packageText = String(data: packageData, encoding: .utf8),
              !containsExternalEntityDeclaration(packageText) else { throw ImportFailure.invalid }
        let package = try SwiftSoup.parseXML(packageData)
        let version = try package.attr("version")
        guard try package.tagName().lowercased() == "package", version.hasPrefix("2.") || version.hasPrefix("3."),
              try package.select("metadata").first() != nil,
              try package.select("manifest").first() != nil,
              try package.select("spine").first() != nil else { throw ImportFailure.invalid }
    }

    static func containsExternalEntityDeclaration(_ xml: String) -> Bool {
        xml.range(of: "<!\\s*ENTITY\\b[^>]*\\bSYSTEM\\b", options: [.regularExpression, .caseInsensitive]) != nil
            || xml.range(of: "<!\\s*ENTITY\\b[^>]*\\bPUBLIC\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func read(_ entry: Entry, from archive: Archive, maximum: Int) async throws -> Data {
        guard maximum >= 0, entry.type == .file, !entry.isEncrypted, entry.uncompressedSize <= UInt64(maximum) else { throw ImportFailure.archiveUnsafe }
        let accumulator = EPUBDataAccumulator(maximumBytes: maximum)
        try await archive.extract(entry, bufferSize: 8192) { chunk in try await accumulator.append(chunk) }
        return await accumulator.value()
    }
}
