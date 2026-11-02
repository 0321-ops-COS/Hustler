import Foundation

/// The page switches the web app keeps in `PIN` (`index.html:726`). A missing
/// pin is off, except Data, which the web app turns on by default.
public struct PagePins: Equatable, Sendable {
    public var log: Bool, data: Bool, earn: Bool, hist: Bool, sync: Bool

    public init(log: Bool = false, data: Bool = true, earn: Bool = false, hist: Bool = false, sync: Bool = false) {
        self.log = log
        self.data = data
        self.earn = earn
        self.hist = hist
        self.sync = sync
    }
}

extension PagePins: Codable {
    private enum CodingKeys: String, CodingKey { case log, data, earn, hist, sync }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? false }
        self.init(
            log: flag(.log),
            data: (try? c.decodeIfPresent(Bool.self, forKey: .data)) ?? true,
            earn: flag(.earn), hist: flag(.hist), sync: flag(.sync)
        )
    }
}

/// The web app's stored settings: `DEF` (`index.html:233`), `zoneGas`,
/// `accSet`, the shortcut fields from `CFG` and the pins from `PIN`.
///
/// Defaults are the web app's exactly, and every missing or unreadable key falls
/// back to its default, never to zero. `CFG`'s Supabase URL and key are backend
/// credentials, not device settings. `settings.monthly` stays out too: those
/// months are `StatementStoreDocument.monthly`, the shape reconciliation reads.
///
/// `schemaVersion` plays the role of the web app's `settings.version`.
public struct AppSettings: Equatable, Sendable {
    public static let currentVersion = 1

    public var schemaVersion: Int
    public var accept: Double, estPay: Double, estMph: Double, mpg: Double, wear: Double, gas: Double
    public var rampTop: Double, rampLow: Double, floorMile: Double, floorHour: Double
    public var baseMile: Double, baseHour: Double, bigItems: Double, bigMile: Double, bigHour: Double
    public var emergency: Double, taxRate: Double, target: Double
    public var caWage: Double, caPct: Double, caMile: Double
    public var zoneGas: [String: Double]
    public var accSet: Bool
    public var shortcutName: String, shortcutLink: String, appUrl: String
    public var pins: PagePins

    public init(
        accept: Double = 89, estPay: Double = 7, estMph: Double = 20,
        mpg: Double = 17.5, wear: Double = 0.12, gas: Double = 5.75,
        rampTop: Double = 90, rampLow: Double = 85, floorMile: Double = 0.75, floorHour: Double = 10,
        baseMile: Double = 1.5, baseHour: Double = 18,
        bigItems: Double = 3, bigMile: Double = 2, bigHour: Double = 20,
        emergency: Double = 80, taxRate: Double = 0.70, target: Double = 85,
        caWage: Double = 16.90, caPct: Double = 120, caMile: Double = 0.37,
        zoneGas: [String: Double] = [:], accSet: Bool = false,
        shortcutName: String = "DoorDash Offer Analyzer", shortcutLink: String = "", appUrl: String = "",
        pins: PagePins = PagePins(), schemaVersion: Int = AppSettings.currentVersion
    ) {
        self.schemaVersion = schemaVersion
        self.accept = accept; self.estPay = estPay; self.estMph = estMph
        self.mpg = mpg; self.wear = wear; self.gas = gas
        self.rampTop = rampTop; self.rampLow = rampLow
        self.floorMile = floorMile; self.floorHour = floorHour
        self.baseMile = baseMile; self.baseHour = baseHour
        self.bigItems = bigItems; self.bigMile = bigMile; self.bigHour = bigHour
        self.emergency = emergency; self.taxRate = taxRate; self.target = target
        self.caWage = caWage; self.caPct = caPct; self.caMile = caMile
        self.zoneGas = zoneGas; self.accSet = accSet
        self.shortcutName = shortcutName; self.shortcutLink = shortcutLink; self.appUrl = appUrl
        self.pins = pins
    }

    /// The subset the existing engines take, so the stored document never has to
    /// be passed through the calculations.
    public func verdictSettings() -> VerdictSettings {
        VerdictSettings(
            gas: gas, mpg: mpg, wear: wear, rampTop: rampTop, rampLow: rampLow,
            floorMile: floorMile, floorHour: floorHour, baseMile: baseMile, baseHour: baseHour,
            bigItems: bigItems, bigMile: bigMile, bigHour: bigHour,
            emergency: emergency, zoneGas: zoneGas
        )
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case accept, estPay, estMph, mpg, wear, gas
        case rampTop, rampLow, floorMile, floorHour, baseMile, baseHour
        case bigItems, bigMile, bigHour, emergency
        case taxRate, target, caWage, caPct, caMile
        case zoneGas, accSet, shortcutName, shortcutLink, appUrl, pins
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentVersion else {
            throw StoreDocumentError.unsupportedVersion(version)
        }

        let d = AppSettings()
        self.init(
            accept: Self.number(c, .accept, or: d.accept),
            estPay: Self.number(c, .estPay, or: d.estPay),
            estMph: Self.number(c, .estMph, or: d.estMph),
            mpg: Self.number(c, .mpg, or: d.mpg),
            wear: Self.number(c, .wear, or: d.wear),
            // `num(s.gas)>0 ? s.gas : DEF.gas` — the web loader refuses a zero gas price.
            gas: Self.number(c, .gas, or: d.gas, mustBePositive: true),
            rampTop: Self.number(c, .rampTop, or: d.rampTop),
            rampLow: Self.number(c, .rampLow, or: d.rampLow),
            floorMile: Self.number(c, .floorMile, or: d.floorMile),
            floorHour: Self.number(c, .floorHour, or: d.floorHour),
            baseMile: Self.number(c, .baseMile, or: d.baseMile),
            baseHour: Self.number(c, .baseHour, or: d.baseHour),
            bigItems: Self.number(c, .bigItems, or: d.bigItems),
            bigMile: Self.number(c, .bigMile, or: d.bigMile),
            bigHour: Self.number(c, .bigHour, or: d.bigHour),
            emergency: Self.number(c, .emergency, or: d.emergency),
            taxRate: Self.number(c, .taxRate, or: d.taxRate),
            target: Self.number(c, .target, or: d.target),
            caWage: Self.number(c, .caWage, or: d.caWage),
            caPct: Self.number(c, .caPct, or: d.caPct),
            caMile: Self.number(c, .caMile, or: d.caMile),
            zoneGas: Self.gasPrices(c, or: d.zoneGas),
            accSet: (try? c.decodeIfPresent(Bool.self, forKey: .accSet)) ?? d.accSet,
            shortcutName: (try? c.decodeIfPresent(String.self, forKey: .shortcutName)) ?? d.shortcutName,
            shortcutLink: (try? c.decodeIfPresent(String.self, forKey: .shortcutLink)) ?? d.shortcutLink,
            appUrl: (try? c.decodeIfPresent(String.self, forKey: .appUrl)) ?? d.appUrl,
            pins: (try? c.decodeIfPresent(PagePins.self, forKey: .pins)) ?? d.pins,
            schemaVersion: version
        )
    }

    /// `num()` plus the loader's finite-number check: a JSON number, or a numeric
    /// string from hand-edited JSON. Anything else is the default.
    private static func number(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys,
        or fallback: Double, mustBePositive: Bool = false
    ) -> Double {
        var decoded = try? c.decodeIfPresent(Double.self, forKey: key)
        if decoded == nil, let text = try? c.decodeIfPresent(String.self, forKey: key) {
            decoded = Double(text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        }
        guard let value = decoded, value.isFinite, !mustBePositive || value > 0 else { return fallback }
        return value
    }

    /// One bad zone drops that entry, not the whole map; a missing map is empty.
    private static func gasPrices(
        _ c: KeyedDecodingContainer<CodingKeys>, or fallback: [String: Double]
    ) -> [String: Double] {
        guard let nested = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .zoneGas) else {
            return fallback
        }
        var prices: [String: Double] = [:]
        for key in nested.allKeys {
            if let value = try? nested.decode(Double.self, forKey: key), value.isFinite {
                prices[key.stringValue] = value
            }
        }
        return prices
    }
}

/// Device settings, read and written only through `LocalStore`, so the same
/// rules apply: a missing file is a first run and yields the defaults, while a
/// file that cannot be read leaves writes blocked and is kept until `recover()`.
public final class SettingsStore {
    public let store: LocalStore
    public private(set) var settings: AppSettings
    public private(set) var status: LocalLibrary.Status

    public init(store: LocalStore = LocalStore()) {
        self.store = store
        do {
            if let stored = try store.load(AppSettings.self, from: .settings) {
                settings = stored
                status = .loaded
            } else {
                settings = AppSettings()
                status = .missing
            }
        } catch {
            settings = AppSettings()
            status = .unavailable(error.localizedDescription)
        }
    }

    public var isUnavailable: Bool {
        if case .unavailable = status { return true }
        return false
    }

    /// Adopted only after the write succeeded; a refused write changes nothing.
    @discardableResult
    public func save(_ candidate: AppSettings) throws -> AppSettings {
        if isUnavailable { throw LocalStore.Failure.blocked(.settings) }
        try store.save(candidate, as: .settings)
        settings = candidate
        status = .loaded
        return candidate
    }

    /// Moves the unreadable file aside under a free name and lifts the block.
    /// Nothing is deleted, and the settings fall back to the defaults.
    @discardableResult
    public func recover() throws -> URL? {
        let kept = try store.quarantine(.settings)
        settings = AppSettings()
        status = .missing
        return kept
    }
}
