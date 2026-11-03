import SwiftUI
import Combine
import HustlerCore

/// App shell. `NavigationPlan` decides which pages are visible and in what
/// order; this file only draws that list and wires each page's view.
struct RootView: View {
    @StateObject private var nav = NavigationViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppScreen = .scoreboard

    var body: some View {
        TabView(selection: $selection) {
            ForEach(nav.plan.screens) { screen in
                NavigationStack {
                    AppScreenView(
                        screen: screen,
                        onOpenData: { selection = .data },
                        onPinsChanged: { nav.reload() }
                    )
                }
                .tabItem { Label(screen.title, systemImage: Self.icon(for: screen)) }
                .tag(screen)
            }
        }
        .onAppear { nav.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { nav.reload() }
        }
        // A pin can take away the page you are on; fall back to the first tab.
        .onChange(of: nav.plan) { _, plan in
            if !plan.screens.contains(selection) { selection = plan.screens[0] }
        }
    }

    /// SF Symbols are the only thing the shell chooses for the bar.
    static func icon(for screen: AppScreen) -> String {
        switch screen {
        case .scoreboard: return "house"
        case .check: return "checkmark.seal"
        case .whatIf: return "slider.horizontal.3"
        case .data: return "tray.and.arrow.down"
        case .settings: return "gear"
        case .log: return "doc.text"
        case .earn: return "dollarsign.circle"
        case .hist: return "clock.arrow.circlepath"
        case .sync: return "arrow.left.arrow.right"
        }
    }
}

/// One screen per destination. `HomeView` is the web Scoreboard; every other
/// page already exists, so the tab bar and the Settings page share this switch.
struct AppScreenView: View {
    let screen: AppScreen
    var onOpenData: () -> Void = {}
    var onPinsChanged: () -> Void = {}

    var body: some View {
        switch screen {
        case .scoreboard: HomeView(onOpenData: onOpenData)
        case .check: CheckView()
        case .whatIf: WhatIfView()
        case .data: DataView()
        case .settings: SettingsView(onPinsChanged: onPinsChanged)
        case .log: LogView()
        case .earn: EarningsView()
        case .hist: HistoryView()
        case .sync: HandoffView()
        }
    }
}

/// Re-reads the stored pins so a change made in Settings reaches the bar
/// immediately. Nothing is cached beyond the current plan.
@MainActor
final class NavigationViewModel: ObservableObject {
    @Published private(set) var plan = NavigationPlan.make(pins: PagePins())
    private let store: LocalStore

    init(store: LocalStore = LocalStore()) {
        self.store = store
        reload()
    }

    func reload() {
        plan = NavigationPlan.make(pins: SettingsStore(store: store).settings.pins)
    }
}

#Preview {
    RootView()
}
