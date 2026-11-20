import Foundation

struct ImportResult: Equatable {
    let sourceURL: URL
    let record: BookRecord?
    let failure: ImportFailure?
    var succeeded: Bool { record != nil && failure == nil }
}
