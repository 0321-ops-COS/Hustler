import Foundation
import Combine
import HustlerCore

/// Home's read-only analytics: loads the stored log and settings, runs the
/// existing core functions and formats their rows in the core's order. It never
/// sorts or recalculates a total.
@MainActor
final class AnalyticsViewModel: ObservableObject {

    struct Row: Identifiable, Equatable {
        let id: String
        let label: String
        let values: [String]
    }

    struct MatrixRow: Identifiable, Equatable {
        let id: String
        let label: String
        let orders: String
        let netPerHour: String
        let agrees: Bool
    }

    @Published private(set) var matrixRows: [MatrixRow] = []
    @Published private(set) var zoneRows: [Row] = []
    @Published private(set) var hourRows: [Row] = []
    @Published private(set) var monthRows: [Row] = []
    @Published private(set) var taxRows: [Row] = []

    /// The web tables' empty states and the tax disclaimer, verbatim.
    let zoneHint = "Add a zone column to the log to see this."
    let hourHint = "Add a time column (like 12:40) to see this."
    let monthHint = "Needs dates like 2026-10-24 in the log."
    let taxHint = "Estimate from your log, not tax advice. Check the current IRS rate."

    private let store: LocalStore

    init(store: LocalStore = LocalStore()) {
        self.store = store
        reload()
    }

    /// Re-reads the log and saved settings, so Statements changes show up.
    func reload() {
        let library = LocalLibrary(store: store)
        guard !library.isUnavailable(.masterLog) else {
            matrixRows = []; zoneRows = []; hourRows = []; monthRows = []; taxRows = []
            return
        }

        let settings = SettingsStore(store: store).settings
        let verdict = settings.verdictSettings()
        let taxRate = settings.taxRate
        let rows = MasterLog.orderedForAnalysis(MasterLogParser.parse(library.log.text))

        zoneRows = Analytics.zones(rows, settings: verdict).map { zone in
            Row(id: zone.zone, label: zone.zone, values: [
                "\(zone.orders)", zone.netPerHour.map { Money.format($0) } ?? "--",
                zone.netPerMile.map { Money.format($0) } ?? "--"
            ])
        }
        hourRows = Analytics.hours(rows, settings: verdict).map { hour in
            Row(id: "\(hour.hour)", label: hour.label, values: [
                "\(hour.orders)", hour.netPerHour.map { Money.format($0) } ?? "--"
            ])
        }
        monthRows = Analytics.months(rows, settings: verdict, taxRate: taxRate).map { month in
            Row(id: month.month, label: month.month, values: [
                "\(month.orders)", Money.format(month.gross), JsNumber.toFixed(month.miles, places: 0),
                Money.format(month.net), Money.format(month.mileageDeduction)
            ])
        }

        let tax = Analytics.taxEstimate(rows, settings: verdict, taxRate: taxRate)
        taxRows = [
            Row(id: "gross", label: "Gross dash income", values: [Money.format(tax.gross)]),
            Row(id: "miles", label: "Business miles", values: [JsNumber.toFixed(tax.miles, places: 1)]),
            Row(id: "deduction", label: "Mileage deduction at \(Money.format(taxRate))/mi",
                values: [Money.format(tax.mileageDeduction)]),
            Row(id: "taxable", label: "Taxable after mileage", values: [Money.format(tax.taxable)])
        ]

        matrixRows = VerdictMatrix.cells(rows, settings: verdict).map { cell in
            MatrixRow(id: cell.label, label: cell.label, orders: "\(cell.orders)",
                      netPerHour: cell.netPerHour.map { Money.format($0) } ?? "--", agrees: cell.agrees)
        }
    }
}
