import XCTest
@testable import HustlerCore

/// Expected values come from executing the web app's `$f()` and `num()`
/// (`ios-app/tools/parity/expectations.json`), including the `toFixed` tie
/// cases where Swift's default formatting would differ.
final class MoneyTests: XCTestCase {

    func testFormatMatchesWebAppToFixed() {
        XCTAssertEqual(Money.format(1.5), "$1.50")
        XCTAssertEqual(Money.format(0), "$0.00")
        XCTAssertEqual(Money.format(-2.5), "$-2.50")
        XCTAssertEqual(Money.format(1234.5), "$1234.50")
        // Ties and near-ties: JS toFixed gives 0.13 / 1.00 / 2.67 / 0.01 / 1.33.
        XCTAssertEqual(Money.format(0.125), "$0.13")
        XCTAssertEqual(Money.format(1.005), "$1.00")
        XCTAssertEqual(Money.format(2.675), "$2.67")
        XCTAssertEqual(Money.format(0.005), "$0.01")
        XCTAssertEqual(Money.format(1.335), "$1.33")
    }

    func testFormatHandlesNonFinite() {
        XCTAssertEqual(Money.format(.nan), "$0.00")
        XCTAssertEqual(Money.format(.infinity), "$0.00")
        XCTAssertEqual(Money.format(-.infinity), "$0.00")
    }

    func testParseMatchesWebAppNum() {
        XCTAssertEqual(Money.parse("12.5"), 12.5, accuracy: 1e-12)
        XCTAssertEqual(Money.parse("$1,234.5"), 1234.5, accuracy: 1e-12)
        XCTAssertEqual(Money.parse(""), 0)
        XCTAssertEqual(Money.parse("abc"), 0)
        XCTAssertEqual(Money.parse("12.5abc"), 12.5, accuracy: 1e-12)
        XCTAssertEqual(Money.parse(".5"), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Money.parse("-3"), -3, accuracy: 1e-12)
        XCTAssertEqual(Money.parse("$"), 0)
        // JavaScript parseFloat("1e3") === 1000
        XCTAssertEqual(Money.parse("1e3"), 1000, accuracy: 1e-12)
    }

    func testParseOptionalDistinguishesUnparseableInput() {
        XCTAssertNil(Money.parseOptional("n/a"))
        XCTAssertNil(Money.parseOptional(""))
        XCTAssertNil(Money.parseOptional("$"))
        XCTAssertNotNil(Money.parseOptional("0"))
    }

    func testJsNumberDescriptionDropsTrailingZero() {
        XCTAssertEqual(JsNumber.description(20), "20")
        XCTAssertEqual(JsNumber.description(21.5), "21.5")
        XCTAssertEqual(JsNumber.description(44.8), "44.8")
        XCTAssertEqual(JsNumber.description(720), "720")
    }
}
