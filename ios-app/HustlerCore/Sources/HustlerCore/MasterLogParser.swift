import Foundation

/// `parse()` from `index.html:348`, ported field for field.
///
/// Two behaviours are deliberately preserved because the web app relies on them:
/// - `parse` does not validate: it will return rows whose payout is not a number
///   or whose date is not a date. `MasterLog.normalize` is what drops those.
/// - the CSV branch splits on commas naively (no quoting), and keeps `minutes`
///   exactly as written rather than deriving it.
public enum MasterLogParser {

    public static func parse(_ text: String) -> [LogRow] {
        let lines = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let first = lines.first else { return [] }
        if first.hasPrefix("|") { return parsePipe(lines) }
        guard lines.count >= 2 else { return [] }
        return parseCSV(lines)
    }

    private static func parsePipe(_ lines: [String]) -> [LogRow] {
        var rows: [LogRow] = []

        for line in lines where line.hasPrefix("|") {
            var cells = MasterLog.cells(ofPipeLine: line)
            guard let head = cells.first, !head.isEmpty else { continue }
            if head.range(of: "^[-: ]+$", options: .regularExpression) != nil { continue }
            if head.lowercased() == "date" || head == "#" { continue }

            if MasterLog.isAllDigits(head), cells.count > 1, MasterLog.startsWithISODate(cells[1]) {
                cells.removeFirst()
            }
            guard let dateCell = cells.first else { continue }

            let dateParts = dateCell.split(whereSeparator: { $0.isWhitespace })
            let date = dateParts.first.map { String($0) } ?? ""
            let time = dateParts.count > 1 ? String(dateParts[1]) : ""

            func cell(_ index: Int) -> String { index < cells.count ? cells[index] : "" }

            let miles = Money.parse(cell(2))
            let items = Money.parse(cell(3))
            let net = Money.parse(cell(5))
            let hourly = Money.parse(cell(6))
            let rawMinutes = cell(12)

            let minutes: String
            if !rawMinutes.isEmpty, Money.parse(rawMinutes) > 0 {
                minutes = rawMinutes
            } else if hourly > 0, net > 0 {
                minutes = JsNumber.description(JsNumber.rounded(net / hourly * 60, places: 1))
            } else {
                minutes = JsNumber.description(JsNumber.rounded(10 + miles * 2.5 + items * 2, places: 1))
            }

            rows.append(LogRow(
                date: date,
                time: time,
                zone: cell(11),
                payout: cell(1),
                miles: cell(2),
                items: cell(3),
                perMile: cell(4),
                net: cell(5),
                hourly: cell(6),
                verdict: cell(7),
                rate: cell(8),
                choice: cell(9),
                slack: cell(10),
                minutes: minutes,
                source: cell(13)
            ))
        }

        return rows
    }

    private static func parseCSV(_ lines: [String]) -> [LogRow] {
        let header = lines[0]
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        return lines.dropFirst().map { line in
            let values = line.components(separatedBy: ",")
            var fields: [String: String] = [:]
            for (index, name) in header.enumerated() where !name.isEmpty {
                fields[name] = index < values.count
                    ? values[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
            }
            return LogRow(
                date: fields["date"] ?? "",
                time: fields["time"] ?? "",
                zone: fields["zone"] ?? "",
                payout: fields["payout"] ?? "",
                miles: fields["miles"] ?? "",
                items: fields["items"] ?? "",
                perMile: fields["per mile"] ?? fields["permile"] ?? "",
                net: fields["net"] ?? "",
                hourly: fields["hourly"] ?? "",
                verdict: fields["verdict"] ?? "",
                rate: fields["acceptance rate"] ?? fields["rate"] ?? "",
                choice: fields["choice"] ?? "",
                slack: fields["slack"] ?? "",
                minutes: fields["minutes"] ?? "",
                source: fields["source"] ?? ""
            )
        }
    }
}
