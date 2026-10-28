import Foundation

/// Verdict words, ported from the web app's `yes()` and `took()` helpers.
///
/// `yes()` matches "accept", "take", "yes", "worth", "good" or "go" and rejects
/// anything containing "decline", "pass" or the word "no". `took()` only looks
/// at "accept" and "declin". These are intentionally loose and are preserved
/// verbatim so verdicts match the web app.
public enum TextPredicates {

    public static func yes(_ text: String) -> Bool {
        matches("accept|take|yes|worth|good|go", text) && !matches("decline|pass|no\\b", text)
    }

    public static func took(_ text: String) -> Bool {
        matches("accept", text) && !matches("declin", text)
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
