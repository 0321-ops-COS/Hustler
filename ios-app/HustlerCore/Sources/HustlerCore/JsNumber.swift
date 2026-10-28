import Foundation

/// Number formatting and rounding that reproduces the JavaScript idioms the web
/// app depends on. Swift's `String(format:)` rounds exact binary ties to even,
/// while ECMAScript's `toFixed` rounds them up, so `Money`/minutes derivation
/// cannot use it directly.
public enum JsNumber {

    /// Reproduces `n.toFixed(places)` for finite input: round the exact binary
    /// value half-up (ties towards +infinity, matching ECMAScript's "pick the
    /// larger n"), then print with exactly `places` decimals.
    public static func toFixed(_ value: Double, places: Int) -> String {
        guard value.isFinite else { return "NaN" }
        let digits = max(0, min(20, places))
        let factor = pow(10.0, Double(digits))
        let scaled = value * factor
        guard scaled.isFinite, abs(scaled) < 9_007_199_254_740_992 else {
            return String(format: "%.\(digits)f", value)
        }
        let lower = scaled.rounded(.down)
        let fraction = scaled - lower
        let rounded = fraction < 0.5 ? lower : lower + 1
        return String(format: "%.\(digits)f", rounded / factor)
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
}
