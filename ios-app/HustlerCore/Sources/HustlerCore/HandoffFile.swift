import Foundation

/// The web app's handoff file (`#exp`, `index.html:442`): `{app, version,
/// settings, csv}`, where `settings` uses the `draft()` / `DEF` key names and
/// `csv` is the master log. `brief` is not read; the AI brief is another job.
///
/// Decoding is tolerant so web and native files both import: unknown keys are
/// ignored, missing ones default through `AppSettings`, and a web file's absent
/// `schemaVersion` reads as the current version. Only a JSON object with a
/// `settings` object or a `csv` string is a handoff file, so a refused file can
/// leave the device untouched.
public struct HandoffFile: Equatable, Sendable {
    public static let appName = "Hustle HQ"
    public static let currentVersion = 1
    public var settings: AppSettings
    /// The keys the file's `settings` object carried; an import applies only these.
    public var settingsKeys: Set<String>
    /// `csv`: the master log, header included.
    public var log: String?

    public init(settings: AppSettings = AppSettings(), settingsKeys: Set<String> = [], log: String? = nil) {
        self.settings = settings; self.settingsKeys = settingsKeys; self.log = log
    }

    private struct Document: Encodable { let app: String, version: Int, settings: AppSettings, csv: String }

    /// `AppSettings` already encodes the `draft()` key names.
    public static func export(settings: AppSettings, log: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(app: appName, version: currentVersion, settings: settings, csv: log))
    }
    public static func decode(_ text: String) -> HandoffFile? { decode(Data(text.utf8)) }

    public static func decode(_ data: Data) -> HandoffFile? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var settings = AppSettings()
        var keys: Set<String> = []
        if let raw = root["settings"] as? [String: Any] {
            // Web files have no `schemaVersion`. A settings object that still will
            // not decode is no patch, not a silent reset to the defaults.
            var patched = raw
            if patched["schemaVersion"] == nil { patched["schemaVersion"] = currentVersion }
            if let decoded = Self.decodedSettings(patched) { settings = decoded; keys = Set(raw.keys) }
        }
        let log = root["csv"] as? String
        guard log != nil || !keys.isEmpty else { return nil }
        return HandoffFile(settings: settings, settingsKeys: keys, log: log)
    }

    /// Only the keys the file carries replace anything; a key with no setting
    /// behind it is dropped.
    public func mergedSettings(into current: AppSettings) -> AppSettings {
        guard !settingsKeys.isEmpty, var base = Self.dictionary(from: current),
              let patch = Self.dictionary(from: settings) else { return current }
        for key in settingsKeys { if let value = patch[key] { base[key] = value } }
        return Self.decodedSettings(base) ?? current
    }

    /// Additive: rows merge through `mergeLog()` and never replace the log.
    public func importPlan(currentSettings: AppSettings, currentLog: String) -> HandoffImportPlan {
        let before = MasterLog.rowCount(currentLog)
        let merged = log.map { MasterLog.merge(current: currentLog, adding: $0) } ?? currentLog
        return HandoffImportPlan(settings: mergedSettings(into: currentSettings), log: merged,
                                 rowsAdded: max(0, MasterLog.rowCount(merged) - before))
    }
    private static func dictionary(from settings: AppSettings) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(settings) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    private static func decodedSettings(_ dictionary: [String: Any]) -> AppSettings? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}
/// What one import would write, computed before anything is saved.
public struct HandoffImportPlan: Equatable, Sendable {
    public var settings: AppSettings, log: String, rowsAdded: Int

    public init(settings: AppSettings, log: String, rowsAdded: Int) {
        self.settings = settings; self.log = log; self.rowsAdded = rowsAdded
    }
}
