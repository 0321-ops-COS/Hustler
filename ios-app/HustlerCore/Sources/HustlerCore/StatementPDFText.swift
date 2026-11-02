import Foundation

#if canImport(PDFKit)
import PDFKit

/// Page-one text extraction for earnings statements, replacing the web app's
/// pdf.js path (`pdfText()`, `index.html:452`).
///
/// Same scope as the web app: **page one only**, no OCR, no network. pdf.js
/// feeds its text items into `map(x => x.str).join(" ")`, so this joins PDFKit's
/// lines with single spaces and collapses whitespace runs before parsing; that
/// is an extraction detail and does not change any parsing rule.
///
/// Pasted text does not go through here: it goes straight to
/// `StatementParser.parse`, exactly as the web app's paste box does.
public enum StatementPDFText {

    /// Returns page one's text, or `nil` when the data is not a readable PDF or
    /// the page carries no text (an image-only scan, for instance — the caller
    /// should offer the paste box rather than retry).
    public static func pageOne(from data: Data) -> String? {
        guard let document = PDFDocument(data: data),
              document.pageCount > 0,
              let page = document.page(at: 0),
              let text = page.string
        else { return nil }
        return normalized(text)
    }

    /// Convenience for a security-scoped file URL the caller has already opened.
    public static func pageOne(contentsOf url: URL) -> String? {
        guard let document = PDFDocument(url: url),
              document.pageCount > 0,
              let page = document.page(at: 0),
              let text = page.string
        else { return nil }
        return normalized(text)
    }

    /// Collapses all whitespace (newlines included) to single spaces, so text
    /// assembled line by line parses like pdf.js's space-joined items.
    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
#endif
