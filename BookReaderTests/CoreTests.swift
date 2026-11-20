import Foundation
import XCTest
@testable import BookReaderCore

final class CoreTests: XCTestCase {
    func testReadingLocationsRoundTripAcrossSupportedDocuments() throws {
        let locations: [ReadingLocation] = [
            ReadingLocation(position: .pdf(page: 4, anchorX: 0.2, anchorY: 0.8)),
            ReadingLocation(position: .text(offset: 1234, normalizationVersion: 1)),
            ReadingLocation(position: .epub(locatorJSON: "{\"href\":\"chapter.xhtml\"}", locatorVersion: 1))
        ]
        for location in locations {
            XCTAssertEqual(try JSONDecoder().decode(ReadingLocation.self, from: JSONEncoder().encode(location)), location)
        }
    }

    func testLocationDecodingClampsNegativePageAndTextOffset() throws {
        let cases: [(String, ReadingLocation.Position)] = [
            ("{\"position\":{\"type\":\"pdf\",\"page\":-2},\"savedAt\":0}", .pdf(page: 0, anchorX: nil, anchorY: nil)),
            ("{\"position\":{\"type\":\"text\",\"offset\":-7,\"normalizationVersion\":1},\"savedAt\":0}", .text(offset: 0, normalizationVersion: 1))
        ]
        for (json, expected) in cases {
            XCTAssertEqual(try JSONDecoder().decode(ReadingLocation.self, from: Data(json.utf8)).position, expected)
        }
    }
    func testTextDecoderAcceptsUTF8AndUTF16BOMButRejectsInvalidUTF8() throws {
        XCTAssertEqual(try TextDecoder.decode(data: Data([0xEF, 0xBB, 0xBF]) + Data("Tiếng Việt".utf8)), "Tiếng Việt")
        let littleEndian = Data([0xFF, 0xFE]) + Data("Đọc offline".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        XCTAssertEqual(try TextDecoder.decode(data: littleEndian), "Đọc offline")
        let bigEndian = Data([0xFE, 0xFF]) + Data("Hello".utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
        XCTAssertEqual(try TextDecoder.decode(data: bigEndian), "Hello")
        XCTAssertThrowsError(try TextDecoder.decode(data: Data([0xFF, 0xFF])))
    }

    func testFormatRegistryIsCaseInsensitiveAndHasExplicitScope() {
        XCTAssertEqual(BookFormatRegistry.supportedExtensions, ["epub", "pdf", "txt"])
        XCTAssertEqual(BookFormatRegistry.format(forPathExtension: "PDF"), .pdf)
        XCTAssertEqual(BookFormatRegistry.format(forPathExtension: ".Txt"), .txt)
        XCTAssertEqual(BookFormatRegistry.format(forPathExtension: "EPUB"), .epub)
        XCTAssertNil(BookFormatRegistry.format(forPathExtension: "mobi"))
    }

    func testExternalDTDAndEntityDeclarationsAreRejected() {
        XCTAssertTrue(EPUBArchivePreflight.containsExternalEntityDeclaration("<!DOCTYPE package [<!ENTITY x SYSTEM 'https://example.invalid'>]>"))
        XCTAssertTrue(EPUBArchivePreflight.containsExternalEntityDeclaration("<!ENTITY x PUBLIC '-//evil' 'file:///etc/passwd'>"))
        XCTAssertFalse(EPUBArchivePreflight.containsExternalEntityDeclaration("<package version=\"3.0\"><metadata/></package>"))
    }
    func testEPUBMetadataReaderReadsNamespaceTitleAndAuthor() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try await Archive(url: url, accessMode: .create)
        try await add("META-INF/container.xml", "<?xml version=\"1.0\"?><container><rootfiles><rootfile full-path=\"OEBPS/content.opf\"/></rootfiles></container>", to: archive)
        try await add("OEBPS/content.opf", "<?xml version=\"1.0\"?><package version=\"3.0\" xmlns=\"http://www.idpf.org/2007/opf\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><metadata><dc:title>Thử &amp; đọc</dc:title><dc:creator>Nguyễn Văn A</dc:creator></metadata><manifest><item id=\"cover\" href=\"images/cover.jpg\" properties=\"cover-image\"/></manifest><spine/></package>", to: archive)
        let metadata = try await EPUBMetadataReader.read(url: url, fallbackTitle: "fallback")
        XCTAssertEqual(metadata.title, "Thử & đọc")
        XCTAssertEqual(metadata.author, "Nguyễn Văn A")
        XCTAssertEqual(metadata.coverPath, "OEBPS/images/cover.jpg")
    }
    func testEPUBPreflightRejectsTraversalAndExternalEntities() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try await Archive(url: url, accessMode: .create)
        try await add("META-INF/container.xml", "<?xml version=\"1.0\"?><container><rootfiles><rootfile full-path=\"../outside.opf\"/></rootfiles></container>", to: archive)
        try await add("OEBPS/content.opf", "<!DOCTYPE package [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><package version=\"3.0\"><metadata/><manifest/><spine/></package>", to: archive)
        do {
            try await EPUBArchivePreflight.validate(url: url)
            XCTFail("Unsafe EPUB was accepted")
        } catch let failure as ImportFailure {
            XCTAssertEqual(failure, .invalid)
        }
    }

    private func add(_ path: String, _ text: String, to archive: Archive) async throws {
        let bytes = Data(text.utf8)
        try await archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count)) { position, size in
            let start = Int(position)
            let end = min(start + size, bytes.count)
            return start < end ? Data(bytes[start..<end]) : Data()
        }
    }

}
