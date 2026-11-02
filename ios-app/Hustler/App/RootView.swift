import SwiftUI

/// App shell. Only the Home card and the statement pipeline are reachable for
/// now; every other screen from the web app is still unported.
struct RootView: View {
    var body: some View {
        NavigationStack {
            HomeView()
        }
    }
}

#Preview {
    RootView()
}
