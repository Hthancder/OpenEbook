import Foundation
import ReadiumShared

/// Local archive reading is handled by Readium's file resource factory.
/// An HTTP client must never forward a publication request to a network stack.
struct EPUBOfflineHTTPClient: HTTPClient {
    func stream(
        request: HTTPRequestConvertible,
        consume: @escaping (_ chunk: Data, _ progress: Double?) -> HTTPResult<Void>
    ) async -> HTTPResult<HTTPResponse> {
        .failure(.security(ImportFailure.networkPolicy))
    }
}
