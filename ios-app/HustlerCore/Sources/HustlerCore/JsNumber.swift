import Foundation

/// Number formatting and rounding that reproduces the JavaScript idioms the web
/// app depends on. Swift's `String(format:)` rounds exact binary ties to even
/// and ECMAScript's `toFixed` rounds them up, so plain formatting is not enough.
public enum JsNumber {

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Reproduces `n.toFixed(places)` for finite input.
    ///
    /// ECMAScript rounds the *exact* value of the binary double. Neither
    /// `String(format:)` nor `Decimal(value)` starts from that value: the former
    /// rounds ties to even, and the latter starts from the shortest decimal that
    /// round-trips (`Decimal(1.335)` is `1.335`, while the stored double is
    /// `1.3349999999999999644...`, which JavaScript prints as `1.33`).
    ///
    /// So the exact value is rebuilt from the IEEE-754 fields as
    /// `significand * 2^exponent` in `Decimal` — halving a decimal is exact, and
    /// the only rounding is at 38 significant digits, far below the precision
    /// that decides a 2-decimal tie — then scaled and rounded half-up.
    ///
    /// Known difference: on an exact negative tie (e.g. `-0.125`) this rounds
    /// away from zero (`-0.13`) while ECMAScript picks the larger value
    /// (`-0.12`). No current input path produces a negative tie; if one appears,
    /// handle it here and add a test.
    public static func toFixed(_ value: Double, places: Int) -> String {
        guard value.isFinite else { return "NaN" }
        let digits = max(0, min(20, places))
        guard digits <= 8, abs(value) < 1e13, let exact = exactDecimal(value) else {
            return String(format: "%.\(digits)f", locale: posix, value)
        }

        var scaled = exact
        for _ in 0..<digits { scaled *= 10 }

        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)

        let asDouble = NSDecimalNumber(decimal: rounded).doubleValue / pow(10.0, Double(digits))
        return String(format: "%.\(digits)f", locale: posix, asDouble)
    }

    /// Reproduces the web app's `+(n).toFixed(places)` pattern: round to a
    /// decimal place and keep a number.
    public static func rounded(_ value: Double, places: Int) -> Double {
        guard value.isFinite else { return 0 }
        return Double(toFixed(value, places: places)) ?? 0
    }

    /// Reproduces JavaScript's `String(number)`, which prints whole numbers
    /// without a trailing `.0` (the web app relies on this for `minutes`).
    public static func description(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return "\(value)"
    }

    /// The exact decimal value of a finite double, or `nil` for subnormals and
    /// magnitudes outside the range this formatter supports.
    private static func exactDecimal(_ value: Double) -> Decimal? {
        let bits = value.bitPattern
        let exponentBits = (bits >> 52) & 0x7FF
        let fraction = bits & 0x000F_FFFF_FFFF_FFFF
        let isNegative = (bits >> 63) != 0

        guard exponentBits != 0x7FF else { return nil }

        var significand: Decimal
        var exponent: Int
        if exponentBits == 0 {
            guard fraction != 0 else { return 0 }
            significand = Decimal(fraction)
            exponent = -1074
        } else {
            significand = Decimal(fraction | (1 << 52))
            exponent = Int(exponentBits) - 1075
        }

        if exponent >= 0 {
            guard exponent < 64 else { return nil }
            for _ in 0..<exponent { significand *= 2 }
        } else {
            guard exponent > -200 else { return nil }
            for _ in 0..<(-exponent) { significand /= 2 }
        }

        return isNegative ? -significand : significand
    }
}
