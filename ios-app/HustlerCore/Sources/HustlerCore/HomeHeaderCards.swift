import Foundation

/// The two cards above the Scoreboard, ported from `renderStart()` (`:515`) and
/// `renderMaster()` (`:361`) in `index.html`.
///
/// Both are presentation: this type decides *which* sentence each state shows
/// and keeps the web app's wording verbatim, so the cards can never disagree
/// with the Scoreboard they introduce. Formatting a number and drawing a card
/// are left to the caller.
public enum HomeStartCard {

    /// One checklist row. `action` is the web app's button label (`"Add"` or
    /// `"Open"`); the rate step has no button on the web, so it is empty.
    public struct Step: Equatable, Sendable {
        public let title: String
        public let detail: String
        public let isDone: Bool
        public let action: String
    }

    public struct Card: Equatable, Sendable {
        /// `"Start here"` until every step is done, then `"Your numbers"`.
        public let title: String
        /// The intro sentence, present only in the start state.
        public let lead: String?
        /// Empty once the card is complete; the web then shows only the note.
        public let steps: [Step]
        /// The exact/estimated month sentence, `nil` when no archive month has
        /// a statement yet.
        public let note: String?
        public let isComplete: Bool
    }

    /// `renderStart()`'s state. `rows` should be the analysed log
    /// (`MasterLog.orderedForAnalysis`); only rows with source `archive`
    /// contribute months, as `r.src==="archive"` does on the web.
    public static func card(
        rows: [LogRow],
        statementMonths: [String],
        hasAcceptanceRate: Bool,
        acceptanceRate: Double
    ) -> Card {
        let archiveRows = rows.filter { $0.isArchive }

        // `(r.date||"").slice(0,7)` keeps any non-empty prefix, as the web does.
        var monthSet: Set<String> = []
        for row in archiveRows {
            let month = String(row.date.prefix(7))
            if !month.isEmpty { monthSet.insert(month) }
        }

        let months = monthSet.sorted()
        let stated = Set(statementMonths)
        let exact = months.filter { stated.contains($0) }
        let estimated: [String]
        if let firstExact = exact.first {
            estimated = months.filter { !stated.contains($0) && $0 >= firstExact }
        } else {
            estimated = months.filter { !stated.contains($0) }
        }

        let hasArchive = !archiveRows.isEmpty
        let hasStatements = !stated.isEmpty
        let complete = hasArchive && hasStatements && hasAcceptanceRate

        return Card(
            title: complete ? "Your numbers" : "Start here",
            lead: complete
                ? nil
                : "Bring in your real history first so every number builds on your account, not a blank page.",
            steps: complete ? [] : [
                Step(
                    title: "DoorDash data_archive.zip",
                    detail: hasArchive
                        ? "\(archiveRows.count) deliveries loaded"
                        : "Gives every delivery's date, time, store and item count.",
                    isDone: hasArchive,
                    action: hasArchive ? "Open" : "Add"
                ),
                Step(
                    title: "Monthly statement PDFs",
                    detail: hasStatements
                        ? "\(stated.count) months read. These set your exact monthly pay."
                        : "Sets exact monthly pay. Without them, pay is only a flat estimate.",
                    isDone: hasStatements,
                    action: hasStatements ? "Open" : "Add"
                ),
                Step(
                    title: "Your acceptance rate",
                    detail: hasAcceptanceRate
                        ? "Saved at " + JsNumber.description(acceptanceRate) + "%."
                        : "In DoorDash, open Ratings > Acceptance rate and copy the Accepted and Declined counts from Last 100 offers.",
                    isDone: hasAcceptanceRate,
                    action: ""
                )
            ],
            note: exact.isEmpty ? nil : noteText(exact: exact, estimated: estimated),
            isComplete: complete
        )
    }

    private static func noteText(exact: [String], estimated: [String]) -> String {
        var text = "Exact: " + exact.joined(separator: ", ") + " (monthly total is your statement)."
        if !estimated.isEmpty {
            text += " Estimated: " + estimated.joined(separator: ", ")
                + " (no statement yet, pay uses your per-delivery estimate)."
        }
        return text + " Per-delivery pay and miles are always estimates that add up to the statement total."
    }
}

/// The master-file tile: row count and the newest row, from `renderMaster()`.
public enum HomeMasterTile {

    public struct Card: Equatable, Sendable {
        public let title: String
        public let text: String
    }

    public static let title = "Master file"

    /// `rows` in analysis order, so the last row is the one the web calls
    /// newest. The missing-time space before the full stop is the web app's
    /// own formatting (`date + " " + time`), kept so both clients read alike.
    public static func card(rows: [LogRow]) -> Card {
        guard let newest = rows.last else {
            return Card(title: title, text: "Empty. Add rows or files to start it.")
        }

        let count = rows.count
        let countText = count == 1 ? "1 row" : "\(count) rows"
        return Card(title: title, text: countText + ". Newest: " + newest.date + " " + newest.time + ".")
    }
}
