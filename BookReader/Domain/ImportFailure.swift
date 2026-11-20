import Foundation

enum ImportFailure: Error, Codable, Equatable {
    case unsupported
    case invalid
    case tooLarge
    case duplicate(existingID: UUID)
    case io
    case protected
    case decoding
    case archiveUnsafe
    case networkPolicy

    var message: String {
        switch self {
        case .unsupported: return "Định dạng này chưa được hỗ trợ."
        case .invalid: return "Tệp không hợp lệ hoặc bị hỏng."
        case .tooLarge: return "Tệp vượt quá giới hạn nhập."
        case .duplicate: return "Sách này đã có trong thư viện."
        case .io: return "Không thể đọc hoặc lưu tệp."
        case .protected: return "Tệp được bảo vệ bằng mật khẩu hoặc DRM."
        case .decoding: return "Không thể giải mã nội dung văn bản."
        case .archiveUnsafe: return "Gói EPUB không vượt qua kiểm tra an toàn."
        case .networkPolicy: return "Không thể bật chính sách chặn tài nguyên mạng; EPUB không được mở."
        }
    }
}
