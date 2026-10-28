import XCTest
@testable import HustlerCore

#if canImport(PDFKit)
import Foundation
import CoreGraphics
import CoreText
import PDFKit

/// PDFKit is Apple-only, so these tests compile and run on the macOS CI job and
/// are absent on the Linux toolchain used for local runs. Every PDF here is
/// generated at runtime: no statement file is committed.
final class StatementPDFTests: XCTestCase {

    private func makePDF(pages: [[String]]) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw XCTSkip("CGDataConsumer is unavailable")
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw XCTSkip("CGContext is unavailable")
        }

        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for page in pages {
            context.beginPDFPage(nil)
            for (index, line) in page.enumerated() {
                let attributed = NSAttributedString(
                    string: line,
                    attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
                )
                let ctLine = CTLineCreateWithAttributedString(attributed)
                context.textPosition = CGPoint(x: 40, y: 740 - CGFloat(index) * 20)
                CTLineDraw(ctLine, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    func testExtractsPageOneAndParsesTheStatement() throws {
        let pdf = try makePDF(pages: [[
            "DoorDash, Inc.",
            "October 2026 Statement",
            "Total Payouts $1,234.56",
            "Payouts (123)"
        ]])

        let text = try XCTUnwrap(StatementPDFText.pageOne(from: pdf))
        XCTAssertTrue(text.contains("Total Payouts"))
        let statement = try XCTUnwrap(StatementParser.parse(text))
        XCTAssertEqual(statement.month, "2026-10")
        XCTAssertEqual(statement.total, 1234.56, accuracy: 1e-9)
        XCTAssertEqual(statement.payouts, 123)
    }

    func testOnlyPageOneIsRead() throws {
        let pdf = try makePDF(pages: [
            ["October 2026 Statement", "Total Payouts $100.00", "Payouts (10)"],
            ["November 2026 Statement", "Total Payouts $999.00", "Payouts (99)"]
        ])

        let text = try XCTUnwrap(StatementPDFText.pageOne(from: pdf))
        XCTAssertFalse(text.contains("November"))
        let statement = try XCTUnwrap(StatementParser.parse(text))
        XCTAssertEqual(statement.month, "2026-10")
        XCTAssertEqual(statement.total, 100, accuracy: 1e-9)
    }

    func testUnreadableDataReturnsNil() {
        XCTAssertNil(StatementPDFText.pageOne(from: Data("not a pdf".utf8)))
        XCTAssertNil(StatementPDFText.pageOne(from: Data()))
    }

    func testNormalizationJoinsLinesAndCollapsesWhitespace() {
        XCTAssertEqual(
            StatementPDFText.normalized("October\n2026  Statement\tTotal\r\nPayouts"),
            "October 2026 Statement Total Payouts"
        )
    }
}
#endif
