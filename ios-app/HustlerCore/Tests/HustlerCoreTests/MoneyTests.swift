import XCTest
@testable import HustlerCore

final class MoneyTests: XCTestCase {

    func testFormatsTwoDecimals() {
        XCTAssertEqual(Money.format(1.5), "$1.50")
        XCTAssertEqual(Money.format(0), "$0.00")
        XCTAssertEqual(Money.format(1234.5), "$1234.50")
        // Web parity: "$" + (-2.5).toFixed(2) === "$-2.50"
        XCTAssertEqual(Money.format(-2.5), "$-2.50")
    }

    func testFormatsNonFiniteAsZero() {
        XCTAssertEqual(Money.format(.nan), "$0.00")
        XCTAssertEqual(Money.format(.infinity), "$0.00")
        XCTAssertEqual(Money.format(-.infinity), "$0.00")
    }

    func testParsesCurrencyAndThousandsSeparators() {
        XCTAssertEqual(Money.parse("$1,234.5"), 1234.5, accuracy: 0.0001)
        XCTAssertEqual(Money.parse(" 12.50 "), 12.50, accuracy: 0.0001)
    }

    func testParsesLeadingNumericPrefixLikeParseFloat() {
        XCTAssertEqual(Money.parse("12.5abc"), 12.5, accuracy: 0.0001)
        XCTAssertEqual(Money.parse(".5"), 0.5, accuracy: 0.0001)
    }

    func testUnparseableInputBecomesZero() {
        XCTAssertEqual(Money.parse(""), 0)
        XCTAssertEqual(Money.parse("abc"), 0)
        XCTAssertEqual(Money.parse("$"), 0)
    }
}
