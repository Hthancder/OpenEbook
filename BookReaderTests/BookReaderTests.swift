import Foundation
import XCTest
@testable import BookReader

final class BookReaderTests: XCTestCase {
    func testSupportedExtensionsMatchUserFacingPicker() {
        XCTAssertEqual(BookFormatRegistry.supportedExtensions, ["epub", "pdf", "txt"])
        XCTAssertEqual(BookTypeRegistry.supported.compactMap(\.preferredFilenameExtension).sorted(), ["epub", "pdf", "txt"])
    }

    func testImportRecognizesOnlyEnabledFormats() {
        XCTAssertEqual(BookFormatRegistry.format(forPathExtension: "PDF"), .pdf)
        XCTAssertEqual(BookFormatRegistry.format(forPathExtension: ".Txt"), .txt)
        XCTAssertEqual(BookFormatRegistry.format(forPathExtension: "EPUB"), .epub)
        XCTAssertNil(BookFormatRegistry.format(forPathExtension: "mobi"))
    }

    func testFailureMessagesRemainUseful() {
        XCTAssertFalse(ImportFailure.unsupported.message.isEmpty)
        XCTAssertFalse(ImportFailure.protected.message.isEmpty)
        XCTAssertFalse(ImportFailure.decoding.message.isEmpty)
    }
}
