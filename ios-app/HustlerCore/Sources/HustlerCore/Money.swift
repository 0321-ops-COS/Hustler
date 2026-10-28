import Foundation

/// Display formatting and tolerant numeric parsing, ported from the web app's
/// `$f()` and `num()` helpers (`index.html:236-237`).
///
/// Milestone 0 only. No earnings, mileage, tax, acceptance, quest or California
/// guarantee logic lives here. Open defect B1 (statement allocation can count
/// more gross than the statement) is documented and deliberately **not**
/// implemented, so this file changes no financial behaviour.
public enum Money {

    /// Mirrors JavaScript `parseFloat` over a `$`/comma-stripped string: accepts a
    /// leading numeric prefix and returns `0` when nothing parses.
    ///
    /// Not mirrored: exponent notation (`"1e3"` parses as `1` here, `1000` in JS).
    /// No current input path produces it; if one appears, extend this with a test.
    public static func parse(_ text: String) -> Double {
        let cleaned = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var prefix = ""
        var sawDigit = false
        var sawDot = false
        var sawSign = false

        for character in cleaned {
            if character.isNumber {
                prefix.append(character)
                sawDigit = true
            } else if character == ".", !sawDot {
                prefix.append(character)
                sawDot = true
            } else if (character == "-" || character == "+"), prefix.isEmpty, !sawSign {
                prefix.append(character)
                sawSign = true
            } else {
                break
            }
        }

        guard sawDigit, let value = Double(prefix), value.isFinite else { return 0 }
        return value
    }

    /// Mirrors `"$" + n.toFixed(2)`: two decimals, no thousands separators, the
    /// minus sign after the dollar sign, and `"$0.00"` for non-finite input.
    public static func format(_ value: Double, decimals: Int = 2) -> String {
        guard value.isFinite else { return "$0.00" }
        let places = max(0, decimals)
        return "$" + String(format: "%.\(places)f", value)
    }
}
