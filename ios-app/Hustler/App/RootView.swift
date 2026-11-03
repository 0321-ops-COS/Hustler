import SwiftUI

/// App shell: Home reads the stored master log, Statements writes it,
/// History reads the stored archive.
struct RootView: View {
    private enum Tab: Hashable {
        case home, history, check, whatIf, statements, settings
    }

    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(onOpenStatements: { selection = .statements })
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(Tab.history)

            NavigationStack {
                CheckView()
            }
            .tabItem { Label("Check", systemImage: "checkmark.seal") }
            .tag(Tab.check)

            NavigationStack {
                WhatIfView()
            }
            .tabItem { Label("What-if", systemImage: "slider.horizontal.3") }
            .tag(Tab.whatIf)

            NavigationStack {
                StatementImportView()
            }
            .tabItem { Label("Statements", systemImage: "doc.text") }
            .tag(Tab.statements)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(Tab.settings)
        }
    }
}

#Preview {
    RootView()
}
