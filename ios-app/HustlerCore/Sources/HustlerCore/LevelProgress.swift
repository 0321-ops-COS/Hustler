import Foundation

/// Level and XP bar, ported from `analyze()` (`index.html:413-417`).
///
/// Deliveries are accepted rows only (`acc.length`), matching DoorDash's
/// completed-orders count. Past Legend the ladder repeats every 250, named
/// Legend II … Legend XXXIX and then plain numbers from 40, as `rom()` does.
public struct LevelProgress: Equatable, Sendable {
    public struct Tier: Equatable, Sendable {
        public let name: String
        public let floor: Int
    }

    /// `L` in the web app, oldest first.
    public static let tiers = [
        Tier(name: "Rookie", floor: 0),
        Tier(name: "Grinder", floor: 25),
        Tier(name: "Operator", floor: 100),
        Tier(name: "Hustler", floor: 300),
        Tier(name: "Legend", floor: 800)
    ]
    public static let step = 250

    public let deliveries: Int
    public let name: String
    public let floor: Int
    public let ceiling: Int

    /// `Math.max(0, Math.min(100, 100 * (nd - lo) / (hi - lo)))`.
    public var percent: Double {
        min(100, max(0, 100 * Double(deliveries - floor) / Double(ceiling - floor)))
    }
    public var fraction: Double { percent / 100 }
    public var toNext: Int { ceiling - deliveries }
    /// `nm + " · " + nd + " deliveries"`.
    public var headerText: String { name + " · " + String(deliveries) + " deliveries" }
    /// The header's `title`: `(hi - nd) + " deliveries to the next level"`.
    public var nextText: String { String(toNext) + " deliveries to the next level" }

    public static func compute(deliveries: Int) -> LevelProgress {
        let count = max(0, deliveries)
        if count < 800 {
            var index = 0
            for (i, tier) in tiers.enumerated() where count >= tier.floor { index = i }
            return LevelProgress(deliveries: count, name: tiers[index].name,
                                 floor: tiers[index].floor, ceiling: tiers[index + 1].floor)
        }
        let beyond = (count - 800) / step
        let floor = 800 + beyond * step
        return LevelProgress(deliveries: count, name: beyond == 0 ? "Legend" : "Legend " + suffix(beyond + 1),
                             floor: floor, ceiling: floor + step)
    }

    /// `nd = acc.length`: accepted offers, archive rows included.
    public static func compute(rows: [LogRow]) -> LevelProgress {
        compute(deliveries: rows.filter { $0.choiceTook }.count)
    }

    /// `rom()`, used only for Legend II…XXXIX; 40 and up stay digits.
    private static func suffix(_ value: Int) -> String {
        guard value < 40 else { return String(value) }
        var number = value
        var out = ""
        for (amount, symbol) in [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")] {
            while number >= amount { out += symbol; number -= amount }
        }
        return out
    }
}
