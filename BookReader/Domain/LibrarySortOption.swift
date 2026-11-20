import Foundation

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case recent
    case title
    case added
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "Đọc gần đây"
        case .title: return "Tên sách"
        case .added: return "Ngày thêm"
        }
    }
}
