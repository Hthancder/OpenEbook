import Foundation

struct ReaderBookmark: Codable, Equatable, Identifiable {
    let id: UUID
    let locatorJSON: String
    let title: String
    let createdAt: Date
    init(id: UUID = UUID(), locatorJSON: String, title: String, createdAt: Date = Date()) {
        self.id = id; self.locatorJSON = locatorJSON; self.title = title; self.createdAt = createdAt
    }
}
