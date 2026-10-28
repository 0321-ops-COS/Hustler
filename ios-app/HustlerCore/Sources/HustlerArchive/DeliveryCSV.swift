import Foundation
import HustlerCore

/// One delivery, as the delivery file describes it.
///
/// `pickupAt` is optional because the web app falls back to the delivery time
/// when `actual_pickup_time` is absent; a present but unreadable pickup time is
/// not a fallback case — the whole row is rejected, exactly as the web app
/// rejects it.
public struct ArchiveDelivery: Equatable, Sendable {
    public var createdAt: Date
    public var pickupAt: Date?
    public var deliveredAt: Date
    public var store: String
    public var items: Double

    public init(createdAt: Date, pickupAt: Date?, deliveredAt: Date, store: String, items: Double) {
        self.createdAt = createdAt
        self.pickupAt = pickupAt
        self.deliveredAt = deliveredAt
        self.store = store
        self.items = items
    }
}

/// The delivery file after filtering, with its own counts.
///
/// `deliveries` has already passed the web app's two row filters (not cancelled,
/// delivery time present) and its timestamp validation. Interval sanity
/// (`delivery > pickup`) is applied later, in `ArchiveImporter`, because that is
/// where the web app applies it.
public struct DeliveryCSVTable: Equatable, Sendable {
    public var rowsInspected: Int
    public var cancelledSkipped: Int
    public var missingDeliverySkipped: Int
    public var invalidSkipped: Int
    public var deliveries: [ArchiveDelivery]

    public init(
        rowsInspected: Int = 0,
        cancelledSkipped: Int = 0,
        missingDeliverySkipped: Int = 0,
        invalidSkipped: Int = 0,
        deliveries: [ArchiveDelivery] = []
    ) {
        self.rowsInspected = rowsInspected
        self.cancelledSkipped = cancelledSkipped
        self.missingDeliverySkipped = missingDeliverySkipped
        self.invalidSkipped = invalidSkipped
        self.deliveries = deliveries
    }
}

/// `loadDeliv()` from `index.html:491`, minus the archive storage the web app
/// keeps: the same six column names, the same two required columns, the same
/// filtering and the same 16-character timestamp truncation and 90-character
/// store-name cut.
///
/// Column matching is exact after lowercasing, with no trimming — a header the
/// web app would not recognise is not recognised here either. That is a
/// deliberate parity choice, not an oversight.
public enum DeliveryCSV {

    public static let createdAtColumn = "order_created_time"
    public static let pickupAtColumn = "actual_pickup_time"
    public static let deliveredAtColumn = "actual_delivery_time"
    public static let storeColumn = "store_name"
    public static let itemsColumn = "total_item_count"
    public static let statusColumn = "order_status"

    public static func parse(_ text: String) throws -> DeliveryCSVTable {
        // `new TextDecoder("utf-8")` under JSZip drops a leading BOM; do the same
        // so a BOM-prefixed export behaves identically on both sides.
        var body = text
        if body.hasPrefix("\u{FEFF}") {
            body.removeFirst()
        }

        let rows = CSVRows.parse(body)
        let header = (rows.first ?? []).map { $0.lowercased() }

        func column(_ name: String) -> Int {
            header.firstIndex(of: name) ?? -1
        }

        let createdIndex = column(createdAtColumn)
        let pickupIndex = column(pickupAtColumn)
        let deliveredIndex = column(deliveredAtColumn)
        let storeIndex = column(storeColumn)
        let itemsIndex = column(itemsColumn)
        let statusIndex = column(statusColumn)

        var missing: [String] = []
        if createdIndex < 0 { missing.append(createdAtColumn) }
        if deliveredIndex < 0 { missing.append(deliveredAtColumn) }
        guard missing.isEmpty else {
            throw ArchiveImportError.notADeliveryFile(missing: missing)
        }

        var table = DeliveryCSVTable(rowsInspected: rows.count > 1 ? rows.count - 1 : 0)

        func value(_ row: [String], _ index: Int) -> String {
            index >= 0 && index < row.count ? row[index] : ""
        }

        for row in rows.dropFirst() {
            if value(row, statusIndex).lowercased().contains("cancel") {
                table.cancelledSkipped += 1
                continue
            }

            let deliveredRaw = value(row, deliveredIndex)
            guard !deliveredRaw.isEmpty else {
                table.missingDeliverySkipped += 1
                continue
            }

            let pickupRaw = value(row, pickupIndex)
            guard let createdAt = ArchiveTimestamp.date(value(row, createdIndex)),
                  let deliveredAt = ArchiveTimestamp.date(deliveredRaw)
            else {
                table.invalidSkipped += 1
                continue
            }

            let pickupAt: Date?
            if pickupRaw.isEmpty {
                pickupAt = nil
            } else if let parsed = ArchiveTimestamp.date(pickupRaw) {
                pickupAt = parsed
            } else {
                // `(r[1] || r[2])` in the web app: a non-empty pickup string wins
                // even when it is not a date, and an unparseable date makes the
                // whole interval unusable, so the row is dropped.
                table.invalidSkipped += 1
                continue
            }

            table.deliveries.append(ArchiveDelivery(
                createdAt: createdAt,
                pickupAt: pickupAt,
                deliveredAt: deliveredAt,
                store: String(value(row, storeIndex).prefix(90)),
                items: Money.parse(value(row, itemsIndex))
            ))
        }

        return table
    }
}

/// The web app's `T()` plus its date parsing, kept together because the two are
/// one behaviour: truncate to 16 characters, turn the first space into `T`, then
/// read the result as UTC by appending `:00Z`.
enum ArchiveTimestamp {

    /// `v => (v || "").slice(0, 16).replace(" ", "T")`
    static func normalised(_ value: String) -> String {
        let truncated = String(value.prefix(16))
        guard let space = truncated.firstIndex(of: " ") else { return truncated }
        return truncated.replacingCharacters(in: space...space, with: "T")
    }

    /// `+new Date(text + ":00Z")`, i.e. the literal-Z UTC interpretation the web
    /// app uses. Returns `nil` where JavaScript would produce `Invalid Date`.
    static func date(_ value: String) -> Date? {
        let text = normalised(value) + ":00Z"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        guard let date = formatter.date(from: text) else { return nil }
        // `DateFormatter` is lenient about rolled-over components in some locales;
        // round-trip the value so "2026-02-30" is rejected like JavaScript does.
        guard formatter.string(from: date) == text else { return nil }
        return date
    }
}
