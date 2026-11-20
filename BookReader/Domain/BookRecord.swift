import Foundation

struct BookRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let relativePath: String
    let format: BookFormat
    let title: String
    let author: String?
    let fileSize: Int64
    let sha256: String
    let addedAt: Date
    var lastOpenedAt: Date?
    var progress: Double
    var locatorJSON: String?
    var bookmarkJSON: String?
    let coverPath: String?

    init(id: UUID = UUID(), relativePath: String, format: BookFormat, title: String, author: String? = nil, fileSize: Int64, sha256: String, addedAt: Date = Date(), lastOpenedAt: Date? = nil, progress: Double = 0, locatorJSON: String? = nil, bookmarkJSON: String? = nil, coverPath: String? = nil) {
        self.id = id
        self.relativePath = relativePath
        self.format = format
        self.title = title
        self.author = author
        self.fileSize = fileSize
        self.sha256 = sha256
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.progress = min(max(progress.isFinite ? progress : 0, 0), 1)
        self.locatorJSON = locatorJSON
        self.bookmarkJSON = bookmarkJSON
        self.coverPath = coverPath
    }
}
