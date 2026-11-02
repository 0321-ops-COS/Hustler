import Foundation

/// The master-log pipe table: normalisation, dedupe, merge and serialisation,
/// ported from `masterLog()`, `mergeLog()`, `csvToPipe()`, `isArchLine()` and
/// `logRows()` in `index.html:668-688`.
///
/// Expectations for these functions were produced by executing the web app's
/// own code (`ios-app/tools/parity/oracle.mjs`), not by reading it.
public enum MasterLog {

    public static let separator = "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"

    public static let header =
        "| Date | Payout | Miles | Items | Per Mile | Net | Hourly | Verdict | Acceptance rate | Choice | Slack | Zone | Minutes | Source |\n" + separator

    // MARK: - Line helpers

    /// JavaScript `line.split("|").slice(1, -1).map(trim)`.
    public static func cells(ofPipeLine line: String) -> [String] {
        var parts = line.components(separatedBy: "|")
        guard parts.count >= 2 else { return [] }
        parts.removeFirst()
        parts.removeLast()
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// `/^[0-9]{4}-[0-9]{2}-[0-9]{2}/`
    public static func startsWithISODate(_ text: String) -> Bool {
        let prefix = Array(text.prefix(10))
        guard prefix.count == 10 else { return false }
        for (index, character) in prefix.enumerated() {
            if index == 4 || index == 7 {
                if character != "-" { return false }
            } else if !character.isASCII || !character.isNumber {
                return false
            }
        }
        return true
    }

    /// `/\|\s*archive\s*\|\s*$/`
    public static func isArchiveLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("|") else { return false }
        let withoutTrailingPipe = String(trimmed.dropLast())
        guard let lastSeparator = withoutTrailingPipe.lastIndex(of: "|") else { return false }
        let lastCell = String(withoutTrailingPipe[withoutTrailingPipe.index(after: lastSeparator)...])
        return lastCell.trimmingCharacters(in: .whitespaces) == "archive"
    }

    /// `csvToPipe()`: converts a CSV line into a pipe row, or `nil` when the
    /// line cannot be read. Note the 15-column `shortcut` variant drops the
    /// Zone and Minutes columns — that is existing behaviour (defect B6),
    /// preserved here rather than silently "fixed".
    public static func csvToPipe(_ line: String) -> String? {
        let columns = line
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard columns.count >= 9, startsWithISODate(columns[0]) else { return nil }

        func cell(_ index: Int) -> String {
            index < columns.count ? columns[index] : ""
        }

        let source = cell(9)
        let dateText = (cell(0) + " " + cell(1)).trimmingCharacters(in: .whitespaces)

        let mapped: [String]
        if source == "shortcut" && columns.count >= 15 {
            mapped = [dateText, cell(3), cell(4), cell(5), cell(10), cell(11),
                      cell(12), cell(7), cell(13), cell(8), cell(14)]
        } else {
            mapped = [dateText, cell(3), cell(4), cell(5), cell(10), cell(11),
                      cell(12), cell(7), cell(13), cell(8), cell(14), cell(2),
                      cell(6), source]
        }
        return "| " + mapped.joined(separator: " | ") + " |"
    }

    /// `l.replace(/\s+/g, " ").replace(/\s*\|\s*/g, "|")`
    static func dedupeKey(_ line: String) -> String {
        let collapsed = line.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        return collapsed.replacingOccurrences(
            of: "\\s*\\|\\s*", with: "|", options: .regularExpression
        )
    }

    /// `l.replace(/\s+/g, " ")` — used only for archive line counting.
    static func archiveKey(_ line: String) -> String {
        line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func isAllDigits(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: - Normalise / count / merge

    /// `masterLog()`: one canonical text for any input. Exact duplicate shortcut
    /// rows are dropped; duplicate archive rows are kept because two stacked
    /// deliveries can look identical.
    public static func normalize(_ text: String) -> String {
        var kept: [String] = []
        var seen = Set<String>()

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("|") {
                let cells = cells(ofPipeLine: line)
                guard cells.count >= 10,
                      startsWithISODate(cells[0]),
                      Money.parseOptional(cells[1]) != nil
                else { continue }
            } else {
                if line.range(of: "^date\\s*,", options: [.regularExpression, .caseInsensitive]) != nil {
                    continue
                }
                guard line.contains(","), let converted = csvToPipe(line) else { continue }
                line = converted
            }

            if isArchiveLine(line) {
                kept.append(line)
                continue
            }

            let key = dedupeKey(line)
            if seen.contains(key) { continue }
            seen.insert(key)
            kept.append(line)
        }

        return header + (kept.isEmpty ? "" : "\n" + kept.joined(separator: "\n"))
    }

    /// `logRows()`: row count of an already-normalised master log.
    public static func rowCount(_ text: String) -> Int {
        let lines = normalize(text).components(separatedBy: "\n")
        return max(0, lines.count - 2)
    }

    /// `mergeLog()`: adds rows, matching archive lines by count so importing the
    /// same archive twice is idempotent.
    public static func merge(current: String, adding: String) -> String {
        let base = normalize(current)

        var present: [String: Int] = [:]
        for line in base.components(separatedBy: "\n").dropFirst(2) where isArchiveLine(line) {
            present[archiveKey(line), default: 0] += 1
        }

        var incoming: [String: Int] = [:]
        var kept: [String] = []
        for line in normalize(adding).components(separatedBy: "\n").dropFirst(2) {
            if isArchiveLine(line) {
                let key = archiveKey(line)
                incoming[key, default: 0] += 1
                if incoming[key, default: 0] <= (present[key] ?? 0) { continue }
            }
            kept.append(line)
        }

        let combined = base + (kept.isEmpty ? "" : "\n" + kept.joined(separator: "\n"))
        return normalize(combined)
    }

    /// The web app's analysis order: ascending `"date time"`, arrival order
    /// breaking ties (its sort is stable via an index tiebreak).
    public static func orderedForAnalysis(_ rows: [LogRow]) -> [LogRow] {
        rows.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.dateWithTime
                let right = rhs.element.dateWithTime
                if left == right { return lhs.offset < rhs.offset }
                return left < right
            }
            .map { $0.element }
    }
}
