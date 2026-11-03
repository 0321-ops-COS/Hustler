import Foundation

/// One numeric setting the Settings tab edits. `id` and `label` are the web
/// app's `DEF` key and `LBL` caption (`index.html:233-235`); the key path is the
/// stored `AppSettings` value it reads and writes.
public struct SettingsField: Identifiable, Hashable {
    public enum Group: String, CaseIterable, Sendable {
        case verdict, tax, california
        public var title: String { rawValue.capitalized }
    }

    public let id: String
    public let label: String
    public let group: Group
    /// `num(s.gas)>0 ? s.gas : DEF.gas`: the web loader refuses a zero gas price.
    public var mustBePositive: Bool = false
    private let keyPath: WritableKeyPath<AppSettings, Double>

    public func value(in settings: AppSettings) -> Double { settings[keyPath: keyPath] }
    public func set(_ value: Double, in settings: inout AppSettings) { settings[keyPath: keyPath] = value }

    public static let gas = SettingsField(id: "gas", label: "Gas price ($/gal)", group: .verdict, mustBePositive: true, keyPath: \.gas)
    public static let mpg = SettingsField(id: "mpg", label: "MPG", group: .verdict, keyPath: \.mpg)
    public static let wear = SettingsField(id: "wear", label: "Wear cost per mile ($)", group: .verdict, keyPath: \.wear)
    public static let rampTop = SettingsField(id: "rampTop", label: "Ramp top (% acceptance)", group: .verdict, keyPath: \.rampTop)
    public static let rampLow = SettingsField(id: "rampLow", label: "Ramp low (% acceptance)", group: .verdict, keyPath: \.rampLow)
    public static let floorMile = SettingsField(id: "floorMile", label: "Floor $/mile", group: .verdict, keyPath: \.floorMile)
    public static let floorHour = SettingsField(id: "floorHour", label: "Floor $/hour", group: .verdict, keyPath: \.floorHour)
    public static let baseMile = SettingsField(id: "baseMile", label: "Base $/mile", group: .verdict, keyPath: \.baseMile)
    public static let baseHour = SettingsField(id: "baseHour", label: "Base $/hour", group: .verdict, keyPath: \.baseHour)
    public static let bigItems = SettingsField(id: "bigItems", label: "Big order: items over", group: .verdict, keyPath: \.bigItems)
    public static let bigMile = SettingsField(id: "bigMile", label: "Big order $/mile", group: .verdict, keyPath: \.bigMile)
    public static let bigHour = SettingsField(id: "bigHour", label: "Big order $/hour", group: .verdict, keyPath: \.bigHour)
    public static let emergency = SettingsField(id: "emergency", label: "Emergency rate (%)", group: .verdict, keyPath: \.emergency)
    public static let taxRate = SettingsField(id: "taxRate", label: "Mileage deduction rate ($/mi)", group: .tax, keyPath: \.taxRate)
    public static let caWage = SettingsField(id: "caWage", label: "CA minimum wage ($/hr)", group: .california, keyPath: \.caWage)
    public static let caPct = SettingsField(id: "caPct", label: "CA guarantee (% of min wage per active hour)", group: .california, keyPath: \.caPct)
    public static let caMile = SettingsField(id: "caMile", label: "CA guarantee per mile ($)", group: .california, keyPath: \.caMile)

    public static let all: [SettingsField] = [
        gas, mpg, wear, rampTop, rampLow, floorMile, floorHour, baseMile, baseHour,
        bigItems, bigMile, bigHour, emergency, taxRate, caWage, caPct, caMile
    ]
}

/// A settings document plus inline text for any rejected field. Parsing is the
/// web app's `num()`: `$` and commas are stripped and a leading number is kept;
/// empty or unparseable input leaves the old value and records a message.
public struct SettingsEdit: Equatable {
    public private(set) var settings: AppSettings
    public private(set) var messages: [SettingsField: String] = [:]

    public init(_ settings: AppSettings = AppSettings()) { self.settings = settings }

    public func text(for field: SettingsField) -> String { Self.display(field.value(in: settings)) }

    @discardableResult
    public mutating func apply(_ text: String, to field: SettingsField) -> Bool {
        guard let value = Money.parseOptional(text), value.isFinite, !field.mustBePositive || value > 0 else {
            let kept = Self.display(field.value(in: settings))
            messages[field] = field.mustBePositive
                ? "Enter a number above zero. Kept \(kept)."
                : "Enter a number. Kept \(kept)."
            return false
        }
        messages[field] = nil
        field.set(value, in: &settings)
        return true
    }

    public mutating func setShortcutName(_ text: String) { settings.shortcutName = text }
    public mutating func setShortcutLink(_ text: String) { settings.shortcutLink = text }
    public mutating func setPinned(_ page: AppPage, _ on: Bool) { page.setPinned(on, in: &settings.pins) }
    public func isPinned(_ page: AppPage) -> Bool { page.isPinned(in: settings.pins) }
    public var runShortcutURL: URL? { ShortcutRoute.runURL(name: settings.shortcutName) }
    public var shortcutLinkURL: URL? { ShortcutRoute.linkURL(settings.shortcutLink) }

    /// What the web input shows for a stored number: no trailing `.0`.
    static func display(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

/// The web app's `PGS` list (`index.html:725`), with the pin each switch writes.
public struct AppPage: Identifiable, Hashable {
    public let id: String, title: String, subtitle: String
    private let pin: WritableKeyPath<PagePins, Bool>

    public func isPinned(in pins: PagePins) -> Bool { pins[keyPath: pin] }
    public func setPinned(_ on: Bool, in pins: inout PagePins) { pins[keyPath: pin] = on }

    public static let log = AppPage(id: "log", title: "Master file", subtitle: "View, edit and save the master log", pin: \.log)
    public static let data = AppPage(id: "data", title: "Data", subtitle: "Drop offers, statements and archive files", pin: \.data)
    public static let earn = AppPage(id: "earn", title: "Earnings", subtitle: "Read your monthly statements", pin: \.earn)
    public static let hist = AppPage(id: "hist", title: "History", subtitle: "Load your DoorDash data archive", pin: \.hist)
    public static let sync = AppPage(id: "sync", title: "Handoff", subtitle: "Export or import for another AI", pin: \.sync)

    public static let all: [AppPage] = [log, data, earn, hist, sync]
}

/// The two Settings buttons. Nothing asks the system whether a scheme can open;
/// a URL is built from stored text and handed to `openURL`.
public enum ShortcutRoute {
    public static func runURL(name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "shortcuts://run-shortcut?name=" + percentEncoded(trimmed))
    }

    public static func linkURL(_ link: String) -> URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    /// `encodeURIComponent`: only `A-Z a-z 0-9 - _ . ! ~ * ' ( )` survive.
    static func percentEncoded(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
