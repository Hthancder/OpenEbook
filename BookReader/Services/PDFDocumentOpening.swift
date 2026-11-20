import Foundation
import PDFKit

struct PDFDocumentOpening {
    func pageCount(at url: URL) -> Int? {
        guard let document = PDFDocument(url: url), !document.isEncrypted || document.isUnlocked else { return nil }
        return document.pageCount
    }
    func isPasswordProtected(at url: URL) -> Bool { PDFDocument(url: url)?.isEncrypted ?? false }
}
