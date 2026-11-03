import Foundation
import HustlerCore

/// Earnings screen state; `EarningsPage` owns the wording and the numbers.
@MainActor
final class EarningsViewModel: ObservableObject {
    @Published private(set) var page: EarningsPage
    /// A statements file that exists but cannot be read, not "no statements yet".
    @Published private(set) var statementsProblem: String?
    private let store: LocalStore

    init(store: LocalStore = LocalStore()) {
        self.store = store
        let library = LocalLibrary(store: store)
        page = EarningsPage(statements: library.statements, rows: MasterLogParser.parse(library.log.text))
        statementsProblem = Self.problem(in: library)
    }

    /// Re-reads both files; the Data or Statements tab may have changed them.
    func reload() {
        let library = LocalLibrary(store: store)
        statementsProblem = Self.problem(in: library)
        page = EarningsPage(statements: library.statements, rows: MasterLogParser.parse(library.log.text))
    }

    private static func problem(in library: LocalLibrary) -> String? {
        if case let .unavailable(reason) = library.status(of: .statements) { return reason }
        return nil
    }
}
