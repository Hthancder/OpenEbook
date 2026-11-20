import Foundation

struct ReadingLocation: Codable, Equatable {
    enum Position: Codable, Equatable {
        case pdf(page: Int, anchorX: Double?, anchorY: Double?)
        case text(offset: Int, normalizationVersion: Int)
        case epub(locatorJSON: String, locatorVersion: Int)

        private enum CodingKeys: String, CodingKey { case type, page, anchorX, anchorY, offset, normalizationVersion, locatorJSON, locatorVersion }
        private enum Kind: String, Codable { case pdf, text, epub }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            switch try values.decode(Kind.self, forKey: .type) {
            case .pdf:
                self = .pdf(page: max(try values.decode(Int.self, forKey: .page), 0),
                            anchorX: try values.decodeIfPresent(Double.self, forKey: .anchorX),
                            anchorY: try values.decodeIfPresent(Double.self, forKey: .anchorY))
            case .text:
                self = .text(offset: max(try values.decode(Int.self, forKey: .offset), 0),
                             normalizationVersion: try values.decode(Int.self, forKey: .normalizationVersion))
            case .epub:
                self = .epub(locatorJSON: try values.decode(String.self, forKey: .locatorJSON),
                             locatorVersion: try values.decode(Int.self, forKey: .locatorVersion))
            }
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .pdf(page, anchorX, anchorY):
                try values.encode(Kind.pdf, forKey: .type)
                try values.encode(max(page, 0), forKey: .page)
                try values.encodeIfPresent(anchorX, forKey: .anchorX)
                try values.encodeIfPresent(anchorY, forKey: .anchorY)
            case let .text(offset, version):
                try values.encode(Kind.text, forKey: .type)
                try values.encode(max(offset, 0), forKey: .offset)
                try values.encode(version, forKey: .normalizationVersion)
            case let .epub(json, version):
                try values.encode(Kind.epub, forKey: .type)
                try values.encode(json, forKey: .locatorJSON)
                try values.encode(version, forKey: .locatorVersion)
            }
        }
    }

    let position: Position
    let savedAt: Date
    init(position: Position, savedAt: Date = Date()) { self.position = position; self.savedAt = savedAt }
}
