import Foundation

struct LibraryRecovery {
    enum Issue: Equatable {
        case orphanedBookFile(String)
        case interruptedStagingFile(String)
        case missingBookFile(UUID)
    }

    static func inspect(paths: BookPathStore, records: [BookRecord], fileManager: FileManager = .default) -> [Issue] {
        var issues: [Issue] = []
        let recorded = Set(records.map(\.relativePath))
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        if let entries = try? fileManager.contentsOfDirectory(at: paths.booksURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            for entry in entries {
                guard let id = UUID(uuidString: entry.lastPathComponent), (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if let record = recordsByID[id] {
                    if let url = try? paths.resolve(relativePath: record.relativePath), !fileManager.fileExists(atPath: url.path) {
                        issues.append(.missingBookFile(id))
                    }
                } else if let files = try? fileManager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil), files.contains(where: { !$0.lastPathComponent.hasSuffix(".deleting") }) {
                    issues.append(.orphanedBookFile(entry.path))
                }
            }
        }
        if let staging = try? fileManager.contentsOfDirectory(at: paths.stagingURL, includingPropertiesForKeys: nil) {
            issues += staging.map { .interruptedStagingFile($0.lastPathComponent) }
        }
        return issues
    }
}
