import Foundation

struct ImportSecurity {
    static func validateArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return !components.isEmpty && !components.contains(".") && !components.contains("..")
    }
}
