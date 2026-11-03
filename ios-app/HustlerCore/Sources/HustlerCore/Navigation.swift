import Foundation

/// One destination the native app can show. The first five are the web app's
/// fixed nav tabs (`index.html:115-124`); the last four are the `PGS` pages
/// whose nav buttons `applyPins()` shows or hides (`index.html:725-728`).
public enum AppScreen: String, CaseIterable, Identifiable, Sendable {
    case scoreboard, check, whatIf, data, settings, log, earn, hist, sync

    public var id: String { rawValue }

    /// The web nav label. The `PGS` pages keep their `PGS` title, so Data reads
    /// "Data" and the four menu extras read "Master file", "Earnings" and so on.
    public var title: String {
        switch self {
        case .scoreboard: return "Scoreboard"
        case .check: return "Check"
        case .whatIf: return "What-if"
        case .settings: return "Settings"
        case .data, .log, .earn, .hist, .sync: return page?.title ?? rawValue
        }
    }

    /// The `PGS` subtitle (`index.html:725`); the four fixed tabs have none.
    public var subtitle: String? { page?.subtitle }

    /// The `PGS` page this screen shows, or `nil` for the fixed tabs.
    public var page: AppPage? {
        switch self {
        case .data: return .data
        case .log: return .log
        case .earn: return .earn
        case .hist: return .hist
        case .sync: return .sync
        case .scoreboard, .check, .whatIf, .settings: return nil
        }
    }

    /// `applyPins()` hides a `PGS` nav button when its pin is off. The fixed
    /// tabs have no switch in the web app, so they are always visible.
    public func isPinned(in pins: PagePins) -> Bool {
        page.map { $0.isPinned(in: pins) } ?? true
    }
}

extension AppPage {
    /// The screen that shows this `PGS` page. `AppPage.all` is exactly these
    /// five, so the four extra pages fall through to Data, and Data matches
    /// itself.
    public var screen: AppScreen {
        if self == .log { return .log }
        if self == .earn { return .earn }
        if self == .hist { return .hist }
        if self == .sync { return .sync }
        return .data
    }
}

/// What the app's navigation shows, in the web app's order: the fixed tabs,
/// then the pinned `PGS` pages. This is `applyPins()` as data — a pin adds its
/// page to the list and taking the pin off removes it, while Settings still
/// lists every `PGS` page and can open it.
public struct NavigationPlan: Equatable, Sendable {
    /// The visible pages, in web order. Never empty.
    public let screens: [AppScreen]

    public init(screens: [AppScreen]) {
        self.screens = screens.isEmpty ? [.scoreboard] : screens
    }

    public static func make(pins: PagePins) -> NavigationPlan {
        var screens: [AppScreen] = [.scoreboard, .check, .whatIf]
        if AppScreen.data.isPinned(in: pins) { screens.append(.data) }
        screens.append(.settings)
        screens += [AppScreen.log, .earn, .hist, .sync].filter { $0.isPinned(in: pins) }
        return NavigationPlan(screens: screens)
    }
}
