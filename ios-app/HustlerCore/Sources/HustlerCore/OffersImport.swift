import Foundation

/// `skipped` is every inspected row that did not become a new master-log row:
/// already present, duplicate within the file, or unreadable.
public struct OffersImportCounts: Equatable, Sendable {
    public let rowsInspected: Int
    public let newlyAdded: Int
    public let skipped: Int
}

public struct OffersImportResult: Equatable, Sendable {
    public let mergedLog: String
    public let counts: OffersImportCounts
}

/// `route()`/`ingest()` outcomes the screen distinguishes. `deliveryFile` is the
/// `ORDER_CREATED_TIME` check `route()` makes before `ingest()`.
public enum OffersImportOutcome: Equatable, Sendable {
    case imported(OffersImportResult)
    case empty
    case deliveryFile
    case unreadable
}

/// The pure half of offers-file import: no file access, clock or network. It
/// classifies content as `route()` does — `ORDER_CREATED_TIME` means a delivery
/// file, JSON is read as JSON, everything else is pipe/CSV text — then converts,
/// adds the missing header and merges through `MasterLog` without removing an
/// existing row.
public enum OffersImporter {

    public static func outcome(text: String, existingLog: String) -> OffersImportOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if text.prefix(300).lowercased().contains("order_created_time") { return .deliveryFile }
        guard let prepared = prepare(trimmed), MasterLog.rowCount(prepared.rows) > 0 else {
            return .unreadable
        }

        let base = MasterLog.normalize(existingLog)
        let before = MasterLog.rowCount(base)
        let merged = MasterLog.merge(current: base, adding: prepared.rows)
        let added = max(0, MasterLog.rowCount(merged) - before)
        let counts = OffersImportCounts(rowsInspected: prepared.inspected, newlyAdded: added,
                                        skipped: max(0, prepared.inspected - added))
        return .imported(OffersImportResult(mergedLog: merged, counts: counts))
    }

    private struct Prepared {
        var rows: String
        var inspected: Int
    }

    private static func prepare(_ trimmed: String) -> Prepared? {
        let isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
        let json = isJSON ? try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) : nil
        guard let json else { return textRows(trimmed) }

        // The web app's handoff file: `{settings: …, csv: "…"}`.
        if let object = json as? [String: Any], let csv = object["csv"] as? String {
            return textRows(csv.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var inspected = 0
        guard let rows = jsonRows(json, inspected: &inspected), !rows.isEmpty else { return nil }
        return Prepared(rows: rows.joined(separator: "\n"), inspected: inspected)
    }

    /// Text rows, less the master-log header, separator and a `date,…` CSV header.
    private static func textRows(_ text: String) -> Prepared? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isStructure($0) }
        return lines.isEmpty
            ? nil
            : Prepared(rows: lines.joined(separator: "\n"), inspected: lines.count)
    }

    private static func isStructure(_ line: String) -> Bool {
        if line.range(of: "^date\\s*,", options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        guard line.hasPrefix("|") else { return false }
        if MasterLog.cells(ofPipeLine: line).first?.lowercased() == "date" { return true }
        return line.filter { $0 != "|" && $0 != "-" && !$0.isWhitespace }.isEmpty
    }

    private static func jsonRows(_ value: Any, inspected: inout Int) -> [String]? {
        if let object = value as? [String: Any] {
            if let rows = object["rows"] as? [Any] { return jsonRows(rows, inspected: &inspected) }
            inspected += 1
            return jsonRow(object).map { [$0] }
        }
        guard let items = value as? [Any] else { return nil }

        var rows: [String] = []
        for item in items {
            inspected += 1
            if let object = item as? [String: Any], let row = jsonRow(object) {
                rows.append(row)
            } else if let cells = item as? [Any],
                      let row = MasterLog.pipeRow(columns: cells.compactMap(text)) {
                rows.append(row)
            } else if let line = item as? String, line.contains(",") || line.hasPrefix("|") {
                rows.append(line) // `MasterLog` validates pipe and CSV lines.
            }
        }
        return rows
    }

    private static func jsonRow(_ object: [String: Any]) -> String? {
        var fields: [String: String] = [:]
        for (key, value) in object {
            let name = key.lowercased().filter { $0.isLetter || $0.isNumber }
            if fields[name] == nil, let text = text(value) { fields[name] = text }
        }
        func cell(_ names: [String]) -> String {
            names.lazy.compactMap { fields[$0] }.first ?? ""
        }
        let columns = [
            cell(["date", "datetime"]), cell(["time"]), cell(["zone"]), cell(["payout"]),
            cell(["miles", "distance"]), cell(["items", "itemcount"]), cell(["minutes"]),
            cell(["verdict"]), cell(["choice"]), cell(["source"]),
            cell(["permile", "payoutpermile"]), cell(["net", "netpay"]),
            cell(["hourly", "netperhour"]), cell(["acceptancerate", "acceptance", "rate"]),
            cell(["slack"])
        ]
        return columns[0].isEmpty ? nil : MasterLog.pipeRow(columns: columns)
    }

    private static func text(_ value: Any) -> String? {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (value as? NSNumber).map { JsNumber.description($0.doubleValue) }
    }
}
