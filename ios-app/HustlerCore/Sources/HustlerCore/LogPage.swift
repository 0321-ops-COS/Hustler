import Foundation
/// `showCheck()`: per-column number type and bad rows (row numbers start at 2).
public enum LogCheck {
    public struct Column: Equatable, Sendable {
        public let name: String
        public let type: String
        public let check: String
        public let isClean: Bool
    }
    public static let names = ["payout", "miles", "items", "minutes"]
    public static func columns(for rows: [LogRow]) -> [Column] {
        guard !rows.isEmpty else { return [] }
        return names.enumerated().map { position, name in
            var floats = 0, wholes = 0
            var bad: [Int] = []
            for (index, row) in rows.enumerated() {
                let value = [row.payout, row.miles, row.items, row.minutes][position]
                    .trimmingCharacters(in: .whitespaces)
                if value.range(of: #"^\$?-?\d+\.\d+$"#, options: .regularExpression) != nil { floats += 1 }
                else if value.range(of: #"^\$?-?\d+$"#, options: .regularExpression) != nil { wholes += 1 }
                else { bad.append(index + 2) }
            }
            let type = floats > 0 && wholes == 0 ? "float"
                : wholes > 0 && floats == 0 ? "whole numbers"
                : floats + wholes > 0 ? "mixed float and whole" : "no numbers"
            let listed = bad.prefix(5).map(String.init).joined(separator: ", ")
            return Column(name: name, type: type,
                          check: bad.isEmpty ? "all clean" : "\(bad.count) bad (rows \(listed))",
                          isClean: bad.isEmpty)
        }
    }
}
/// The web `#log` page: scope control, `scInfo`, `analyze` + `scSave`, `#clear`,
/// `#demo`, `#pasteRows` / `addRow`. Saves go through `LocalLibrary`, so an
/// unreadable log keeps its block until `recover()`.
public final class LogPageModel {
    public enum Mode: String, CaseIterable, Sendable {
        case day, week, wholeFile
        public var title: String { self == .wholeFile ? "Whole file" : rawValue.capitalized }
        var scope: LogScope.Mode? { self == .day ? .day : self == .week ? .week : nil }
    }
    public let today: String
    public private(set) var mode: Mode = .wholeFile
    public private(set) var scopes: [LogScope.Scope] = []
    public private(set) var key: String?
    public var draft = ""
    public private(set) var rows = 0
    public private(set) var notice: String?
    public private(set) var noticeIsFailure = false
    public private(set) var problem: String?
    public private(set) var columns: [LogCheck.Column] = []
    public private(set) var demoText: String?
    private let library: LocalLibrary
    public init(store: LocalStore = LocalStore(), today: String) {
        library = LocalLibrary(store: store)
        self.today = today
        reload()
    }
    public var isScoped: Bool { mode != .wholeFile }
    public var scopeWord: String { mode == .week ? "week" : "day" }
    public var clearTitle: String { mode == .day ? "Delete day" : "Clear for today" }
    public var demoRows: Int { demoText.map { MasterLog.rowCount($0) } ?? 0 }
    public var needsEmptyScopeConfirmation: Bool { isScoped && key != nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var needsClearConfirmation: Bool { mode == .day && key != nil && key != today }
    private var indexInScopes: Int? { key.flatMap { k in scopes.firstIndex { $0.key == k } } }
    public var canStepOlder: Bool { (indexInScopes ?? scopes.count - 1) < scopes.count - 1 }
    public var canStepNewer: Bool { (indexInScopes ?? 0) > 0 }
    public var info: String {
        guard isScoped, key != nil else {
            return rows > 0 ? "\(rows) rows in the whole file. Scroll the box to see them all." : "Nothing logged yet."
        }
        let count = draft.isEmpty ? 0 : draft.components(separatedBy: "\n").count
        return "Editing \(count) row\(count == 1 ? "" : "s") for this \(scopeWord). Analyze and save puts your changes back into the master log."
    }
    public func setMode(_ mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        demoText = nil; notice = nil
        reload()
    }
    public func select(_ key: String) {
        guard scopes.contains(where: { $0.key == key }) else { return }
        self.key = key
        syncScopeText()
    }
    public func step(older: Bool) {
        guard let index = indexInScopes else { return }
        let next = older ? index + 1 : index - 1
        guard scopes.indices.contains(next) else { return }
        key = scopes[next].key
        syncScopeText()
    }
    public func analyzeAndSave(confirmEmptyScope: Bool = false) {
        guard begin() else { return }
        guard let scope = mode.scope, let key else {
            let document = MasterLogDocument(text: draft)
            guard document.rowCount > 0 else { return announce("Need offers to save.", isFailure: true) }
            return save(document.text, success: "Saved \(document.rowCount) rows.")
        }
        let edited = draft.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if edited.isEmpty && !confirmEmptyScope {
            return announce("That removes every row for this \(scopeWord). Continue?")
        }
        let skipped = edited.filter { MasterLog.rowCount($0) == 0 }.count
        let suffix = skipped == 0 ? "" : " \(skipped) line\(skipped == 1 ? "" : "s") could not be read and "
            + (skipped == 1 ? "was" : "were") + " skipped."
        save(LogScope.replacing(text: library.log.text, mode: scope, key: key, with: draft),
             success: "Saved." + suffix)
    }
    public func clearForToday(confirmed: Bool = false) {
        guard begin() else { return }
        let day = (mode == .day ? key : nil) ?? today
        let isToday = day == today
        let lines = LogScope.rows(in: library.log.text)
        let kept = lines.filter { LogScope.date(of: $0) != day }
        let removed = lines.count - kept.count
        guard removed > 0 else { return announce("No entries for " + (isToday ? "today" : day) + ".", isFailure: true) }
        if mode == .day && !isToday && !confirmed {
            return announce("Delete all \(removed) entries for \(day)?")
        }
        let text = MasterLog.header + (kept.isEmpty ? "" : "\n" + kept.joined(separator: "\n"))
        save(text, success: "\(removed) entries for \(isToday ? "today" : day) cleared.")
    }
    public func tryDemo() {
        demoText = MasterLog.normalize(LogDemo.rows.joined(separator: "\n"))
        announce("Demo data, not saved.")
    }
    public func pasteRows(_ text: String) {
        guard begin() else { return }
        let incoming = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MasterLog.rowCount(MasterLog.normalize(incoming)) > 0 else {
            return announce("That could not be read as a log row.", isFailure: true)
        }
        let current = MasterLog.normalize(library.log.text)
        let merged = MasterLog.merge(current: current, adding: incoming)
        if merged == current {
            return announce("This row is already in your log. Nothing was saved or counted.", isFailure: true)
        }
        save(merged, success: "\(MasterLog.rowCount(merged) - MasterLog.rowCount(current)) new rows added.")
    }
    public func recover() {
        do {
            let kept = try library.recover(.masterLog)
            reload()
            let name = kept.map { " The unreadable file is kept as \($0.lastPathComponent)." } ?? ""
            announce("The master log now starts empty." + name)
        } catch {
            announce(error.localizedDescription, isFailure: true)
        }
    }
    private func begin() -> Bool {
        notice = nil; noticeIsFailure = false; demoText = nil
        if let problem { announce(problem, isFailure: true); return false }
        return true
    }
    private func announce(_ text: String, isFailure: Bool = false) {
        notice = text
        noticeIsFailure = isFailure
    }
    private func save(_ text: String, success: String) {
        do {
            try library.saveLog(text)
            reload()
            announce(success)
        } catch {
            reload()
            announce(error.localizedDescription, isFailure: true)
        }
    }
    private func reload() {
        if case let .unavailable(reason) = library.status(of: .masterLog) {
            problem = reason; scopes = []; key = nil; draft = ""; rows = 0; columns = []; return
        }
        problem = nil
        rows = library.log.rowCount
        if let scope = mode.scope {
            scopes = LogScope.scopes(in: library.log.text, mode: scope)
            key = LogScope.selection(in: scopes, mode: scope, previous: key, today: today)
            syncScopeText()
        } else {
            scopes = []; key = nil
            draft = rows > 0 ? library.log.text : ""
        }
        columns = LogCheck.columns(for: MasterLogParser.parse(library.log.text))
    }
    private func syncScopeText() {
        guard let scope = mode.scope, let key else { return }
        draft = LogScope.text(in: library.log.text, mode: scope, key: key)
    }
}
enum LogDemo {
    static let rows = [
        "| 2026-10-19 11:20 | 9.75 | 4.1 | 2 | 2.38 | 6.02 | 19.60 | TAKE IT | 88.00 | Accept | 5 | Alder | 24 |",
        "| 2026-10-19 12:05 | 4.50 | 6.3 | 1 | 0.71 | -0.42 | -1.60 | SKIP | 88.00 | Declined | 0 | Alder | 16 |",
        "| 2026-10-20 08:15 | 12.00 | 5.0 | 3 | 2.40 | 8.10 | 24.30 | TAKE IT | 89.00 | Accept | 10 | Birch | 20 |",
        "| 2026-10-20 09:00 | 7.25 | 3.2 | 2 | 2.27 | 4.64 | 18.56 | TAKE IT | 89.00 | Accept | 0 | Birch | 15 |"
    ]
}
