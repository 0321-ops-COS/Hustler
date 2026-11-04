import Foundation

/// One `hh_store` row exactly as the web app writes it: the key, its
/// `updated_at`, and the JSON text of `v`.
///
/// The web app's shapes (`index.html`): `settings` is the bare settings object,
/// `log` is `{csv, v}`, `archive` is `{v, r}`, `statements` is `{v, s}` and `ca`
/// is `{v, w}`.
public struct AccountStoreRow: Equatable, Sendable {
    public let key: String
    public let updatedAt: String?
    public let value: Data

    public init(key: String, updatedAt: String?, value: Data) {
        self.key = key
        self.updatedAt = updatedAt
        self.value = value
    }
}

/// Parses `GET /rest/v1/hh_store?select=k,updated_at,v` into its rows.
public enum SupabaseStoreRows {
    public static func parse(_ data: Data) throws -> [AccountStoreRow] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseAccountError.unexpectedResponse
        }
        return try rows.map { row in
            guard let key = row["k"] as? String else { throw SupabaseAccountError.unexpectedResponse }
            return AccountStoreRow(key: key,
                                   updatedAt: row["updated_at"] as? String,
                                   value: try encodedValue(row["v"]))
        }
    }

    /// A missing value stays `null`, which counts as zero items rather than
    /// making the whole response unreadable.
    private static func encodedValue(_ value: Any?) throws -> Data {
        guard let value, !(value is NSNull) else { return Data("null".utf8) }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            throw SupabaseAccountError.unexpectedResponse
        }
        return data
    }
}

/// A plain reason the account's data could not become an import.
public enum AccountPullError: LocalizedError, Equatable {
    /// The account holds no settings and no log.
    case emptyAccount
    /// One key's `v` is not the shape the web app writes.
    case unreadableValue(String)
    /// The account and the phone already agree.
    case nothingNew

    public var errorDescription: String? {
        switch self {
        case .emptyAccount:
            return "This account has no settings or log saved yet, so there is nothing to pull."
        case let .unreadableValue(key):
            return "The account's \(key) could not be read. Nothing was changed on this phone."
        case .nothingNew:
            return "Your account and this phone already match. Nothing was changed."
        }
    }
}

/// One `hh_store` key as the preview shows it: what the account holds against
/// what this phone holds.
public struct AccountDataSet: Equatable, Sendable, Identifiable {
    public let key: String
    public let accountItems: Int
    /// `nil` for a key this build does not import, so no phone number is implied.
    public let phoneItems: Int?
    public let updatedAt: String?
    public let isImported: Bool
    public let note: String?

    public var id: String { key }

    /// `account 12 · phone 9 · updated 2026-11-02T10:00:00Z`
    public var summary: String {
        var parts = ["account \(accountItems)"]
        if let phoneItems { parts.append("phone \(phoneItems)") }
        if let updatedAt { parts.append("updated \(updatedAt)") }
        if let note { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

/// What one pull would write. Built and shown before anything is saved.
public struct AccountPullPlan: Equatable, Sendable {
    public let settings: AppSettings
    public let settingsChanged: Bool
    public let log: String
    public let logChanged: Bool
    public let accountRows: Int
    public let phoneRows: Int
}

/// Turns the account's `hh_store` rows into a preview and one import plan.
///
/// The two keys this build imports are folded into the handoff document
/// `HandoffFile` already reads, so the account's data goes through the same
/// validation and settings mapping as a handoff file instead of a second parser.
/// Nothing here writes anything, and nothing here talks to Supabase.
public enum AccountPull {
    /// What the Scoreboard and the Log read: the settings and the master log.
    public static let importableKeys = ["settings", "log"]

    /// Preview rows in the web app's key order, including the keys this build
    /// does not import yet.
    public static func preview(rows: [AccountStoreRow],
                               currentSettings: AppSettings,
                               currentLog: String) -> [AccountDataSet] {
        let found = rowsByKey(rows)
        return SupabaseStoreSummary.keys.map { key in
            let row = found[key]
            let imported = importableKeys.contains(key)
            return AccountDataSet(
                key: key,
                accountItems: count(for: key, value: row?.value),
                phoneItems: imported ? phoneCount(for: key, settings: currentSettings, log: currentLog) : nil,
                updatedAt: row?.updatedAt,
                isImported: imported,
                note: row == nil ? "missing from the account" : (imported ? nil : "not imported yet")
            )
        }
    }

    /// Items in the account for one key: log rows rather than the `{csv, v}`
    /// wrapper, or the value's own item count.
    public static func count(for key: String, value: Data?) -> Int {
        guard let value,
              let object = try? JSONSerialization.jsonObject(with: value, options: [.fragmentsAllowed])
        else { return 0 }
        if key == "log" {
            guard let map = object as? [String: Any], let csv = map["csv"] as? String else { return 0 }
            return MasterLog.rowCount(csv)
        }
        return SupabaseStoreSummary.itemCount(object)
    }

    /// The whole import plan, or a plain reason there is none. The account's log
    /// replaces the phone's log; an empty account log never wipes history. The
    /// account's settings apply through `HandoffFile.mergedSettings`, so a key
    /// the account does not carry keeps this phone's value.
    public static func plan(rows: [AccountStoreRow],
                            currentSettings: AppSettings,
                            currentLog: String) throws -> AccountPullPlan {
        let found = rowsByKey(rows)
        let settingsRow = found["settings"]
        let logRow = found["log"]
        guard settingsRow != nil || logRow != nil else { throw AccountPullError.emptyAccount }

        var document: [String: Any] = [:]
        if let settingsRow {
            guard let object = try? JSONSerialization.jsonObject(with: settingsRow.value),
                  object is [String: Any] else { throw AccountPullError.unreadableValue("settings") }
            document["settings"] = object
        }
        var accountLog: String?
        if let logRow {
            guard let object = try? JSONSerialization.jsonObject(with: logRow.value) as? [String: Any],
                  let csv = object["csv"] as? String else { throw AccountPullError.unreadableValue("log") }
            document["csv"] = csv
            accountLog = csv
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: document),
              let file = HandoffFile.decode(encoded) else {
            throw AccountPullError.unreadableValue("data")
        }

        let settings = file.mergedSettings(into: currentSettings)
        let accountRows = accountLog.map { MasterLog.rowCount($0) } ?? 0
        let log = accountRows > 0 ? MasterLog.normalize(accountLog ?? "") : MasterLog.normalize(currentLog)
        let plan = AccountPullPlan(settings: settings,
                                   settingsChanged: settings != currentSettings,
                                   log: log,
                                   logChanged: log != MasterLog.normalize(currentLog),
                                   accountRows: accountRows,
                                   phoneRows: MasterLog.rowCount(currentLog))
        guard plan.settingsChanged || plan.logChanged else { throw AccountPullError.nothingNew }
        return plan
    }

    private static func rowsByKey(_ rows: [AccountStoreRow]) -> [String: AccountStoreRow] {
        Dictionary(rows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func phoneCount(for key: String, settings: AppSettings, log: String) -> Int {
        switch key {
        case "settings":
            guard let data = try? JSONEncoder().encode(settings),
                  let object = try? JSONSerialization.jsonObject(with: data) else { return 0 }
            return SupabaseStoreSummary.itemCount(object)
        case "log":
            return MasterLog.rowCount(log)
        default:
            return 0
        }
    }
}

/// A Handoff-format copy of what this phone holds, written before an import.
public enum AccountPullBackup {
    public static let filePrefix = "handoff-before-pull-"

    /// UTC, so two phones and the repo agree on the name.
    public static func fileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return filePrefix + formatter.string(from: now) + ".json"
    }

    /// Writes the phone's current settings and log through `HandoffFile.export`,
    /// the shape the Handoff screen reads back, and returns where it landed.
    @discardableResult
    public static func write(settings: AppSettings, log: String, into directory: URL,
                             now: Date = Date()) throws -> URL {
        let data = try HandoffFile.export(settings: settings, log: log)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(now: now), isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }
}
