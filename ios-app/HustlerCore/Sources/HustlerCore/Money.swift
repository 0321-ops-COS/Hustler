import Foundation

/// Tolerant numeric parsing and money formatting, ported from the web app's
/// `num()` and `$f()` helpers (`index.html:236-237`).
///
/// Milestone 1 port: display formatting only. Defect B1 (statement allocation
/// can count more gross than the statement) is unrelated to this file and
/// remains documented and unimplemented.
public enum Money {

    /// Mirrors JavaScript `parseFloat` over a `$`/comma-stripped string: accepts
    /// a leading numeric prefix (including exponent notation) and returns `nil`
    /// when nothing parses, so callers can keep JavaScript's `isNaN` checks.
    public static func parseOptional(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var prefix = ""
        var index = cleaned.startIndex

        if index < cleaned.endIndex, cleaned[index] == "-" || cleaned[index] == "+" {
            prefix.append(cleaned[index])
            index = cleaned.index(after: index)
        }

        var mantissaDigits = 0
        while index < cleaned.endIndex, cleaned[index].isASCII, cleaned[index].isNumber {
            prefix.append(cleaned[index])
            mantissaDigits += 1
            index = cleaned.index(after: index)
        }

        if index < cleaned.endIndex, cleaned[index] == "." {
            let afterDot = cleaned.index(after: index)
            if afterDot < cleaned.endIndex, cleaned[afterDot].isASCII, cleaned[afterDot].isNumber {
                prefix.append(".")
                index = afterDot
                while index < cleaned.endIndex, cleaned[index].isASCII, cleaned[index].isNumber {
                    prefix.append(cleaned[index])
                    mantissaDigits += 1
                    index = cleaned.index(after: index)
                }
            }
        }

        guard mantissaDigits > 0 else { return nil }

        if index < cleaned.endIndex, cleaned[index] == "e" || cleaned[index] == "E" {
            var exponent = "e"
            var cursor = cleaned.index(after: index)
            if cursor < cleaned.endIndex, cleaned[cursor] == "-" || cleaned[cursor] == "+" {
                exponent.append(cleaned[cursor])
                cursor = cleaned.index(after: cursor)
            }
            var exponentDigits = 0
            while cursor < cleaned.endIndex, cleaned[cursor].isASCII, cleaned[cursor].isNumber {
                exponent.append(cleaned[cursor])
                exponentDigits += 1
                cursor = cleaned.index(after: cursor)
            }
            if exponentDigits > 0 { prefix += exponent }
        }

        guard let value = Double(prefix), value.isFinite else { return nil }
        return value
    }

    /// `num()` as the web app uses it: unparseable input becomes `0`.
    public static func parse(_ text: String) -> Double {
        parseOptional(text) ?? 0
    }

    /// Mirrors `"$" + n.toFixed(2)`: two decimals, no thousands separators, the
    /// minus sign after the dollar sign, `"$0.00"` for non-finite input.
    public static func format(_ value: Double, decimals: Int = 2) -> String {
        guard value.isFinite else { return "$0.00" }
        return "$" + JsNumber.toFixed(value, places: max(0, decimals))
    }
}
