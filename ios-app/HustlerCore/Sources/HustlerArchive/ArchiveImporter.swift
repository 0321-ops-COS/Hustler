import Foundation
import HustlerCore

/// Turns a DoorDash delivery file into archive rows and merges them into the
/// existing master log.
///
/// This is the pure half of the import: no file system, no clock, no network.
/// `prepare` returns the merged log text and the counts; the caller persists the
/// text through `LocalLibrary`, which commits to memory only after the write
/// succeeded and refuses to write an artefact whose file could not be read.
///
/// **Merging, not replacing.** The web app's `toLog()` deletes every archive row
/// and rebuilds them from the archive currently loaded, so importing a newer
/// export silently drops an older export's rows. This port merges instead, using
/// `MasterLog.merge` and its existing normalised-line/count-matched key, so a
/// re-import adds nothing, a superset adds only what is new, and no row from a
/// previous export is ever removed. That divergence is deliberate and approved.
public enum ArchiveImporter {

    /// The web app's `DEF.estPay`: archive rows carry an estimated payout because
    /// the archive has no pay figures at all.
    public static let estimatedPayPerDelivery: Double = 7

    /// The web app's `DEF.estMph`: miles are estimated from active minutes.
    public static let estimatedMilesPerHour: Double = 20

    /// The web app's `CITIES`, in its order. `find()` takes the first match, so
    /// the order is part of the behaviour: a store containing both "Sun City"
    /// and "Menifee" resolves to whichever appears first in this list.
    static let cities = [
        "Murrieta", "Temecula", "Lake Elsinore", "Menifee", "Corona", "Wildomar",
        "Perris", "Winchester", "Sun City", "Canyon Lake", "Fontana", "Riverside",
        "Hemet", "Norco", "Eastvale", "Moreno Valley"
    ]

    public static func prepare(
        archiveData: Data,
        existingLog: String,
        estimatedPay: Double = estimatedPayPerDelivery,
        estimatedMilesPerHour: Double = estimatedMilesPerHour,
        limits: ArchiveLimits = .standard
    ) throws -> ArchiveImportResult {
        let csvData = try DeliveryArchiveFile.deliveryCSV(in: archiveData, limits: limits)
        guard let text = String(data: csvData, encoding: .utf8) else {
            throw ArchiveImportError.deliveryFileUnreadable(reason: "the delivery file is not valid UTF-8")
        }

        let table = try DeliveryCSV.parse(text)

        // `toLog()`: start is eight minutes before pickup, so a single delivery's
        // active window begins before the food was collected.
        struct Timed {
            var start: Date
            var end: Date
            var pickup: Date
            var store: String
            var items: Double
            var order: Int
        }

        var timed: [Timed] = []
        var droppedIntervals = 0

        for (order, delivery) in table.deliveries.enumerated() {
            let pickup = delivery.pickupAt ?? delivery.deliveredAt
            let start = pickup.addingTimeInterval(-8 * 60)
            guard delivery.deliveredAt > start else {
                droppedIntervals += 1
                continue
            }
            timed.append(Timed(
                start: start,
                end: delivery.deliveredAt,
                pickup: pickup,
                store: delivery.store,
                items: delivery.items,
                order: order
            ))
        }

        // JavaScript's sort is stable; the explicit input-order tiebreak keeps
        // equal start times in delivery-file order here too.
        timed.sort { lhs, rhs in
            if lhs.start == rhs.start { return lhs.order < rhs.order }
            return lhs.start < rhs.start
        }

        // Overlapping deliveries share the block's active time equally, exactly
        // as `toLog()` spreads `(end - a) / count` across a stacked run.
        var minutes = [Double](repeating: 0, count: timed.count)
        var index = 0
        while index < timed.count {
            var last = index
            var end = timed[index].end
            while last + 1 < timed.count, timed[last + 1].start < end {
                last += 1
                end = max(end, timed[last].end)
            }
            let share = end.timeIntervalSince(timed[index].start) / Double(last - index + 1) / 60
            for member in index...last {
                minutes[member] = share
            }
            index = last + 1
        }

        var lines: [String] = []
        lines.reserveCapacity(timed.count)

        for (position, delivery) in timed.enumerated() {
            guard let stamp = pacificStamp(delivery.pickup) else {
                throw ArchiveImportError.timeZoneUnavailable
            }
            let zone = cities.first {
                delivery.store.lowercased().contains($0.lowercased())
            } ?? ""
            // `o.i || 1`: a missing or zero item count becomes one item.
            let items = delivery.items == 0 ? 1 : delivery.items
            let cells = [
                stamp.date,
                stamp.time,
                zone,
                JsNumber.toFixed(estimatedPay, places: 2),
                JsNumber.toFixed(minutes[position] / 60 * estimatedMilesPerHour, places: 1),
                JsNumber.description(items),
                String(Int(minutes[position].rounded())),
                "",
                "Accepted",
                "archive"
            ]
            lines.append(cells.joined(separator: ","))
        }

        guard !lines.isEmpty else {
            throw ArchiveImportError.nothingToImport
        }

        let retainedRows = MasterLog.rowCount(existingLog)
        let merged = MasterLog.merge(current: existingLog, adding: lines.joined(separator: "\n"))
        let mergedRows = MasterLog.rowCount(merged)
        let newlyAdded = max(0, mergedRows - retainedRows)
        let alreadyPresent = max(0, lines.count - newlyAdded)

        let counts = ArchiveImportCounts(
            rowsInspected: table.rowsInspected,
            validRows: lines.count,
            cancelledSkipped: table.cancelledSkipped,
            missingDeliverySkipped: table.missingDeliverySkipped,
            invalidSkipped: table.invalidSkipped,
            droppedNonPositiveIntervals: droppedIntervals,
            alreadyPresent: alreadyPresent,
            newlyAdded: newlyAdded,
            retainedRows: retainedRows
        )

        return ArchiveImportResult(mergedLog: merged, counts: counts)
    }

    /// `Intl.DateTimeFormat("en-CA", { timeZone: "America/Los_Angeles", hourCycle: "h23" })`
    /// over the instant the web app built from the literal-Z UTC string.
    private static func pacificStamp(_ date: Date) -> (date: String, time: String)? {
        guard let zone = TimeZone(identifier: "America/Los_Angeles") else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute
        else { return nil }
        return (
            String(format: "%04d-%02d-%02d", year, month, day),
            String(format: "%02d:%02d", hour, minute)
        )
    }
}
