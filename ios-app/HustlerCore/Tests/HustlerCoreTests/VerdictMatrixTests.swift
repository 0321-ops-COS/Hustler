import XCTest
@testable import HustlerCore

/// Hand-checked cases for the web app's `#matrix` table. Fixture rows carry
/// explicit Net and Minutes cells, so every expected figure is arithmetic on
/// the row text rather than a capture of the implementation.
final class VerdictMatrixTests: XCTestCase {
    private let settings = VerdictSettings()

    private func rows(_ lines: [String]) -> [LogRow] {
        MasterLogParser.parse(Fixtures.headerLiteral + "\n" + lines.joined(separator: "\n"))
    }

    /// 20.00 + 22.00 over 1 hour is $42.00/hr; the declined -1.00 over 15 min
    /// is -$4.00/hr; 6.00 over 20 min is $18.00/hr; 0.00 over the parser's
    /// 17-minute fallback (10 + 2.5*2 + 2) is $0.00/hr.
    private let lines = [
        "| 2026-10-27 14:46 | 22.00 | 5.0 | 2 | 4.40 | 20.00 | 40.00 | TAKE IT | 89 | Accept | 0 |  | 30 |",
        "| 2026-10-27 14:50 | 25.00 | 6.0 | 2 | 4.17 | 22.00 | 44.00 | TAKE IT | 89 | Accept | 0 |  | 30 |",
        "| 2026-10-27 15:10 | 4.00 | 6.0 | 2 | 0.67 | -1.00 | -4.00 | TAKE IT | 89 | Declined | 0 |  | 15 |",
        "| 2026-10-27 16:00 | 8.00 | 4.0 | 1 | 2.00 | 6.00 | 18.00 | SKIP | 89 | Accept | 0 |  | 20 |",
        "| 2026-10-27 17:00 | 3.00 | 2.0 | 1 | 1.50 | 0.00 | 0.00 | SKIP | 89 | Declined | 0 |  | 0 |"
    ]

    func testCellsMatchHandCheckedFigures() {
        let cells = VerdictMatrix.cells(rows(lines), settings: settings)
        XCTAssertEqual(cells.map(\.label), [
            "Said yes, you accepted", "Said yes, you declined",
            "Said no, you accepted", "Said no, you declined"
        ])
        XCTAssertEqual(cells.map(\.orders), [2, 1, 1, 1])
        XCTAssertEqual(cells.map(\.agrees), [true, false, false, true])
        XCTAssertEqual(cells.map { $0.netPerHour.map { Money.format($0) } ?? "--" },
                       ["$42.00", "$-4.00", "$18.00", "$0.00"])
        XCTAssertEqual(cells[0].net, 42.00, accuracy: 1e-12)
        XCTAssertEqual(cells[0].minutes, 60, accuracy: 1e-12)
    }

    /// A cell with no time has no rate. Archive rows carry no verdict, so even
    /// an accepted delivery never reaches the matrix.
    func testNoTimeAndArchiveRows() {
        let untimed = LogRow(verdict: "SKIP", choice: "Declined", minutes: "0")
        let cells = VerdictMatrix.cells(rows([Fixtures.archiveRow]) + [untimed], settings: settings)
        XCTAssertEqual(cells.map(\.orders), [0, 0, 0, 1])
        XCTAssertTrue(cells.allSatisfy { $0.netPerHour == nil })
    }

    func testEmptyLogKeepsTheFourRows() {
        let cells = VerdictMatrix.cells([], settings: settings)
        XCTAssertEqual(cells.map(\.orders), [0, 0, 0, 0])
        XCTAssertEqual(cells.map(\.label).count, 4)
    }
}
