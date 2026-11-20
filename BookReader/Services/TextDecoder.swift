import Foundation

struct TextDecoder {
    static let maximumTextFileSize: Int64 = 20 * 1024 * 1024
    static func decode(data: Data) throws -> String {
        guard !data.isEmpty else { throw ImportFailure.invalid }
        if data.starts(with: [0xFF, 0xFE]) {
            guard let value = String(data: Data(data.dropFirst(2)), encoding: .utf16LittleEndian) else { throw ImportFailure.decoding }
            return value
        }
        if data.starts(with: [0xFE, 0xFF]) {
            guard let value = String(data: Data(data.dropFirst(2)), encoding: .utf16BigEndian) else { throw ImportFailure.decoding }
            return value
        }
        let body = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        guard let value = String(data: Data(body), encoding: .utf8) else { throw ImportFailure.decoding }
        return value
    }

    static func decode(url: URL, maximumBytes: Int64 = maximumTextFileSize) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0 else { throw ImportFailure.invalid }
        guard Int64(size) <= maximumBytes else { throw ImportFailure.tooLarge }
        return try decode(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
}
