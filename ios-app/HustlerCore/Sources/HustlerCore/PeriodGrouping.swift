import Foundation

/// Calendar bucketing, ported from `keyOf()` (`index.html:560`).
///
/// The web app slices the date text for day/month/year and, for weeks, anchors
/// the date at **noon local time** before stepping back to Monday — the noon
/// anchor is what stops a timezone from moving the calendar date. Because the
/// bucket is always the same calendar date the device shows, the arithmetic
/// here is done on the y-m-d triple directly and is timezone-independent, which
/// keeps the native result identical on every device.
public enum PeriodGrouping {

    public enum Period: String, CaseIterable, Sendable {
        case day, week, month, year
    }

    /// `keyOf(s, p)`: the bucket a dated row belongs to.
    ///
    /// Returns `""` for text that is not a `yyyy-MM-dd` date. The web app never
    /// reaches that case — every caller filters rows with
    /// `/^\d{4}-\d\d-\d\d/` first — and its own behaviour there is
    /// `"NaN-NaN-NaN"`, which this port deliberately does not reproduce.
    public static func key(for dateText: String, period: Period) -> String {
        let date = String(dateText.prefix(10))
        switch period {
        case .day:
            return date
        case .month:
            return String(date.prefix(7))
        case .year:
            return String(date.prefix(4))
        case .week:
            return monday(ofISO: date) ?? ""
        }
    }

    /// The Monday of the week containing `dateText`, or `nil` when unparseable.
    public static func monday(ofISO dateText: String) -> String? {
        guard let parts = parse(dateText) else { return nil }
        let days = daysFromCivil(parts.year, parts.month, parts.day)
        // 1970-01-01 was a Thursday; JavaScript counts Sunday as 0.
        let weekday = ((days + 4) % 7 + 7) % 7
        let offsetToMonday = (weekday + 6) % 7
        let monday = civilFromDays(days - offsetToMonday)
        return format(monday)
    }

    // MARK: - Date arithmetic (no Calendar, no timezone)

    struct YMD: Equatable {
        var year: Int
        var month: Int
        var day: Int
    }

    static func parse(_ text: String) -> YMD? {
        let characters = Array(text)
        guard characters.count == 10 else { return nil }
        for (index, character) in characters.enumerated() {
            if index == 4 || index == 7 {
                guard character == "-" else { return nil }
            } else {
                guard character.isASCII, character.isNumber else { return nil }
            }
        }
        let pieces = text.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2])
        else { return nil }
        return YMD(year: year, month: month, day: day)
    }

    static func format(_ value: YMD) -> String {
        func pad(_ number: Int, _ width: Int) -> String {
            let text = String(number)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return pad(value.year, 4) + "-" + pad(value.month, 2) + "-" + pad(value.day, 2)
    }

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let shiftedYear = year - (month <= 2 ? 1 : 0)
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Inverse of `daysFromCivil`.
    static func civilFromDays(_ days: Int) -> YMD {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let month = monthPrime + (monthPrime < 10 ? 3 : -9)
        return YMD(year: year + (month <= 2 ? 1 : 0), month: month, day: day)
    }
}
