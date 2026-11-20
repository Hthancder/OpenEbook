import Foundation

struct BookFormatRegistry {
    static let supportedExtensions = ["epub", "pdf", "txt"]
    static func format(forPathExtension pathExtension: String) -> BookFormat? {
        let normalized = pathExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard supportedExtensions.contains(normalized) else { return nil }
        return BookFormat(fileExtension: normalized)
    }
}
