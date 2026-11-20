import Foundation
import UniformTypeIdentifiers

struct BookTypeRegistry {
    static let supported: [UTType] = BookFormatRegistry.supportedExtensions.compactMap(UTType.init(filenameExtension:))
}
