import SwiftUI

/// App shell: Home reads the stored master log, Statements writes it.
struct RootView: View {
    private enum Tab: Hashable {
        case home, statements
    }

    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                StatementImportView()
            }
            .tabItem { Label("Statements", systemImage: "doc.text") }
            .tag(Tab.statements)
        }
    }
}

#Preview {
    RootView()
}
