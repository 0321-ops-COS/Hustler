import SwiftUI

/// App shell: Home reads the stored master log, Statements writes it.
struct RootView: View {
    private enum Tab: Hashable {
        case home, check, statements, settings
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
                CheckView()
            }
            .tabItem { Label("Check", systemImage: "checkmark.seal") }
            .tag(Tab.check)

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
