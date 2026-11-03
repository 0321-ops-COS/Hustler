import Foundation

/// The web app's AI brief (`brief()`, `index.html:441`) and the text its
/// "Copy AI brief" button copies (`#cpBrief`, `index.html:443`): the brief, a
/// blank line, then `LOG:` and the master log verbatim.
///
/// The wording is the web app's, including its rule and column descriptions.
/// Only the two places that describe the web page itself name the native app
/// instead: "this web page" becomes "this native iOS app", and "Rule used by
/// the page" becomes "Rule used by the app".
public enum AIBrief {

    /// `brief()`: the app description, the rule in words, then `JSON.stringify(S)`.
    public static func brief(settings: AppSettings) -> String {
        "HUSTLE HQ HANDOFF\n"
            + "App: DoorDash offer analyzer. An iOS Shortcut decides offers live and logs one pipe-table row per offer; this native iOS app analyzes the log, holds settings and does what-if replay.\n"
            + "Log columns: Date | Payout | Miles | Items | Per Mile | Net | Hourly | Verdict | Acceptance rate | Choice | Slack.\n"
            + "Rule used by the app: net = payout - miles*(gas/mpg+wear). T = clamp((rampTop-rate)/(rampTop-rampLow),0..1). Bars slide from base to floor by T (big orders use bigMile/bigHour when items>bigItems). Take if payout/mile>reqMile and net/hr>reqHour, or if rate<emergency and net>0.\n"
            + "Settings: " + settingsJSON(settings)
    }

    /// `#cpBrief`: the brief, then the master log exactly as stored, so the
    /// order an AI reads is the order the log has. An empty log keeps the
    /// heading and nothing after it, as the web app does.
    public static func copyText(settings: AppSettings, log: String) -> String {
        brief(settings: settings) + "\n\nLOG:\n" + log
    }

    /// `JSON.stringify(S)`: the `DEF` keys in the web object's order, then the
    /// keys the web adds only once they are set. Numbers go through `JsNumber`
    /// so `0.70` prints as `0.7` and `16.90` as `16.9`, exactly as JavaScript
    /// prints them. The web brief emits bare JSON numbers, never `$` amounts,
    /// so `Money` formatting is deliberately not applied here.
    ///
    /// The web app keeps `monthly` in `S`; here those totals belong to the
    /// statement store, not `AppSettings`, so they are not part of the brief.
    /// Zone keys are sorted because Swift dictionaries have no insertion order.
    private static func settingsJSON(_ settings: AppSettings) -> String {
        var parts = [
            "\"accept\":\(number(settings.accept))",
            "\"estPay\":\(number(settings.estPay))",
            "\"estMph\":\(number(settings.estMph))",
            "\"mpg\":\(number(settings.mpg))",
            "\"wear\":\(number(settings.wear))",
            "\"gas\":\(number(settings.gas))",
            "\"rampTop\":\(number(settings.rampTop))",
            "\"rampLow\":\(number(settings.rampLow))",
            "\"floorMile\":\(number(settings.floorMile))",
            "\"floorHour\":\(number(settings.floorHour))",
            "\"baseMile\":\(number(settings.baseMile))",
            "\"baseHour\":\(number(settings.baseHour))",
            "\"bigItems\":\(number(settings.bigItems))",
            "\"bigMile\":\(number(settings.bigMile))",
            "\"bigHour\":\(number(settings.bigHour))",
            "\"emergency\":\(number(settings.emergency))",
            "\"taxRate\":\(number(settings.taxRate))",
            "\"target\":\(number(settings.target))",
            "\"caWage\":\(number(settings.caWage))",
            "\"caPct\":\(number(settings.caPct))",
            "\"caMile\":\(number(settings.caMile))"
        ]
        if !settings.zoneGas.isEmpty {
            let zones = settings.zoneGas.keys.sorted().map { zone in
                "\"\(escaped(zone))\":\(number(settings.zoneGas[zone] ?? 0))"
            }
            parts.append("\"zoneGas\":{" + zones.joined(separator: ",") + "}")
        }
        // The web sets `S.accSet=1` only after the acceptance rate is saved.
        if settings.accSet { parts.append("\"accSet\":1") }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// JavaScript prints numbers without a trailing `.0` and without `$`.
    private static func number(_ value: Double) -> String {
        JsNumber.description(value)
    }

    /// `JSON.stringify` string escaping: quotes, backslashes and control
    /// characters only, with non-ASCII left as it is.
    private static func escaped(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}
