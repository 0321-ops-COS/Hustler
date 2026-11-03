import Foundation

/// The Log page's Day / Week scopes, ported from `dOf()`, `scKey()`,
/// `logSplit()`, `scLabel()`, `scLoad()`, `scShow()` and `scSave()`
/// (`index.html:736-768`). No UI: this is the state the page shows and the text
/// it saves. "Whole file" stays plain `MasterLog`, which is what the web app's
/// whole-file box is.
public enum LogScope {

    public enum Mode: String, CaseIterable, Sendable {
        case day, week
    }

    /// One selectable scope, in `scLoad()`'s order (newest key first).
    public struct Scope: Equatable, Sendable {
        public var key: String
        public var count: Int
        public var label: String
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// `dOf()`: the `yyyy-MM-dd` a pipe row starts with, or `nil` when the first
    /// cell is not a date, so a dateless row belongs to no scope at all.
    public static func date(of line: String) -> String? {
        guard line.hasPrefix("|") else { return nil }
        let text = String(line.dropFirst().drop(while: { $0.isWhitespace }).prefix(10))
        return MasterLog.startsWithISODate(text) ? text : nil
    }

    /// `scKey()`: the scope a row belongs to; weeks are anchored on Monday.
    public static func key(for line: String, mode: Mode) -> String? {
        guard let date = date(of: line) else { return nil }
        return mode == .week ? PeriodGrouping.monday(ofISO: date) : date
    }

    /// `logSplit()`: every row of the canonical whole file.
    public static func rows(in text: String) -> [String] {
        Array(MasterLog.normalize(text).components(separatedBy: "\n").dropFirst(2))
    }

    /// `scLoad()`: the scopes that have rows, newest key first, with the label
    /// the picker shows.
    public static func scopes(in text: String, mode: Mode) -> [Scope] {
        var counts: [String: Int] = [:]
        for line in rows(in: text) {
            guard let key = key(for: line, mode: mode) else { continue }
            counts[key, default: 0] += 1
        }
        return counts.keys.sorted(by: >).map { key in
            let count = counts[key] ?? 0
            return Scope(key: key, count: count, label: label(forKey: key, count: count, mode: mode))
        }
    }

    /// `scLabel(key, n)`: `"Tue Oct 27, 2026 (2)"` for a day and
    /// `"Week of Oct 26 to Nov 1 (3)"` for a week. The week label leaves the
    /// year out, as the web app does. Keys that are not a real calendar date
    /// return `""` instead of the web app's `undefined`/`NaN` text; they cannot
    /// come from a row.
    public static func label(forKey key: String, count: Int, mode: Mode) -> String {
        guard let start = PeriodGrouping.parse(key),
              (1...12).contains(start.month), (1...31).contains(start.day)
        else { return "" }
        let startDays = PeriodGrouping.daysFromCivil(start.year, start.month, start.day)
        let end = PeriodGrouping.civilFromDays(startDays + 6)
        let total = " (" + String(count) + ")"
        if mode == .week {
            return "Week of " + months[start.month - 1] + " " + String(start.day)
                + " to " + months[end.month - 1] + " " + String(end.day) + total
        }
        let weekday = weekdays[((startDays + 4) % 7 + 7) % 7]
        return weekday + " " + months[start.month - 1] + " " + String(start.day)
            + ", " + String(start.year) + total
    }

    /// `scLoad()`'s picker selection: the scope already open when it still has
    /// rows, else the scope for `today`, else the newest. `nil` when the mode
    /// has no rows.
    public static func selection(
        in scopes: [Scope], mode: Mode, previous: String?, today: String
    ) -> String? {
        if let previous, scopes.contains(where: { $0.key == previous }) { return previous }
        let todayKey = mode == .week ? PeriodGrouping.monday(ofISO: today) : today
        if let todayKey, scopes.contains(where: { $0.key == todayKey }) { return todayKey }
        return scopes.first?.key
    }

    /// `scShow()`: the rows of one scope, in file order.
    public static func lines(in text: String, mode: Mode, key: String) -> [String] {
        rows(in: text).filter { self.key(for: $0, mode: mode) == key }
    }

    /// `scShow()`'s text box.
    public static func text(in text: String, mode: Mode, key: String) -> String {
        lines(in: text, mode: mode, key: key).joined(separator: "\n")
    }

    /// `scSave()` through `commitLog()`: the edited lines replace that scope
    /// everywhere in the file, at the position of its first row, and every
    /// other row keeps its order. Blank edited lines are dropped, and the whole
    /// file is then normalised exactly as `commitLog()` stores it, so an edited
    /// line the log cannot read is dropped too. A key with no rows yet appends
    /// at the end.
    public static func replacing(
        text: String, mode: Mode, key: String, with edited: String
    ) -> String {
        let replacement = edited.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var out: [String] = []
        var placed = false
        for line in rows(in: text) {
            if self.key(for: line, mode: mode) == key {
                if !placed {
                    out.append(contentsOf: replacement)
                    placed = true
                }
            } else {
                out.append(line)
            }
        }
        if !placed { out.append(contentsOf: replacement) }
        return MasterLog.normalize(out.joined(separator: "\n"))
    }
}
