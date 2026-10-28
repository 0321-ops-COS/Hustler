import Foundation

/// Settings the offer verdict depends on, with the web app's defaults
/// (`DEF` in `index.html:233`). Fields unrelated to a verdict (est. pay/mph,
/// tax rate, float target, California rates) are not ported yet.
public struct VerdictSettings: Equatable, Sendable {
    public var gas: Double
    public var mpg: Double
    public var wear: Double
    public var rampTop: Double
    public var rampLow: Double
    public var floorMile: Double
    public var floorHour: Double
    public var baseMile: Double
    public var baseHour: Double
    public var bigItems: Double
    public var bigMile: Double
    public var bigHour: Double
    public var emergency: Double
    public var zoneGas: [String: Double]

    public init(
        gas: Double = 5.75,
        mpg: Double = 17.5,
        wear: Double = 0.12,
        rampTop: Double = 90,
        rampLow: Double = 85,
        floorMile: Double = 0.75,
        floorHour: Double = 10,
        baseMile: Double = 1.5,
        baseHour: Double = 18,
        bigItems: Double = 3,
        bigMile: Double = 2,
        bigHour: Double = 20,
        emergency: Double = 80,
        zoneGas: [String: Double] = [:]
    ) {
        self.gas = gas
        self.mpg = mpg
        self.wear = wear
        self.rampTop = rampTop
        self.rampLow = rampLow
        self.floorMile = floorMile
        self.floorHour = floorHour
        self.baseMile = baseMile
        self.baseHour = baseHour
        self.bigItems = bigItems
        self.bigMile = bigMile
        self.bigHour = bigHour
        self.emergency = emergency
        self.zoneGas = zoneGas
    }
}

/// A single offer being judged. `minutes` <= 0 means "derive from distance and
/// item count", exactly like a blank minutes field in the web app.
public struct VerdictOffer: Equatable, Sendable {
    public var payout: Double
    public var miles: Double
    public var items: Double
    public var minutes: Double
    public var zone: String

    public init(payout: Double, miles: Double, items: Double, minutes: Double, zone: String = "") {
        self.payout = payout
        self.miles = miles
        self.items = items
        self.minutes = minutes
        self.zone = zone
    }
}

public struct VerdictResult: Equatable, Sendable {
    public let takeIt: Bool
    public let net: Double
    public let hours: Double
    public let minutes: Double
    public let requiredMile: Double
    public let requiredHour: Double
    public let payoutPerMile: Double
    public let netPerHour: Double
}

/// The shortcut's decision rule, ported from `verdict()` (`index.html:429`).
///
/// `net = payout - miles * (gas/mpg + wear)`, with per-zone gas when the row has
/// a zone. The two required bars slide from base to floor as acceptance falls
/// from `rampTop` to `rampLow`. An offer is taken when it clears both bars, or
/// when acceptance is below `emergency` and net is positive.
public enum VerdictEngine {

    /// `clamp((rampTop - rate) / (rampTop - rampLow), 0, 1)`
    ///
    /// A zero-width ramp yields NaN here, matching the web app's `0/0`; every
    /// comparison against NaN is false, so it fails closed rather than silently
    /// falling back to the base bars.
    public static func ramp(_ settings: VerdictSettings, rate: Double) -> Double {
        let span = settings.rampTop - settings.rampLow
        if span == 0 { return .nan }
        let value = (settings.rampTop - rate) / span
        return min(1, max(0, value))
    }

    /// `10 + miles * 2.5 + items * 2`, unrounded — the web app only rounds this
    /// when deriving `minutes` while parsing, not in the verdict.
    public static func defaultMinutes(miles: Double, items: Double) -> Double {
        10 + miles * 2.5 + items * 2
    }

    public static func evaluate(
        _ offer: VerdictOffer,
        settings: VerdictSettings,
        rate: Double
    ) -> VerdictResult {
        let gasPrice = settings.zoneGas[offer.zone] ?? settings.gas
        let costPerMile = gasPrice / settings.mpg + settings.wear

        let minutes = offer.minutes > 0
            ? offer.minutes
            : defaultMinutes(miles: offer.miles, items: offer.items)
        let hours = minutes / 60
        let net = offer.payout - offer.miles * costPerMile

        let t = ramp(settings, rate: rate)
        let isBigOrder = offer.items > settings.bigItems
        let mileBar = isBigOrder ? settings.bigMile : settings.baseMile
        let hourBar = isBigOrder ? settings.bigHour : settings.baseHour
        let requiredMile = mileBar - t * (mileBar - settings.floorMile)
        let requiredHour = hourBar - t * (hourBar - settings.floorHour)

        let payoutPerMile = offer.miles != 0 ? offer.payout / offer.miles : offer.payout
        let netPerHour = net / hours

        let takeIt = (payoutPerMile > requiredMile && netPerHour > requiredHour)
            || (rate < settings.emergency && net > 0)

        return VerdictResult(
            takeIt: takeIt,
            net: net,
            hours: hours,
            minutes: minutes,
            requiredMile: requiredMile,
            requiredHour: requiredHour,
            payoutPerMile: payoutPerMile,
            netPerHour: netPerHour
        )
    }
}
