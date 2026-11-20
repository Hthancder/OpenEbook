import Foundation

enum BookFormat: String, Codable, CaseIterable, Identifiable {
    case pdf
    case epub
    case txt

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .epub: return "EPUB"
        case .txt: return "TXT"
        }
    }
    var fileExtension: String { rawValue }
    init?(fileExtension: String) {
        switch fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "pdf": self = .pdf
        case "epub": self = .epub
        case "txt": self = .txt
        default: return nil
        }
    }
}
