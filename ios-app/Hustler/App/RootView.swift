import SwiftUI
import HustlerCore

/// App shell. Only the statement pipeline is reachable for now; every other
/// screen from the web app is still unported.
struct RootView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Statement import") {
                        StatementImportView()
                    }
                    Text("Monthly totals from a statement PDF or pasted text. Each month's total replaces that month's estimated archive pay, to the cent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Earnings")
                }

                Section("Not ported yet") {
                    Text("Check and What-if, History, Earn, quests, the California guarantee, and the master-log editor beyond raw text.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Hustler")
        }
    }
}

#Preview {
    RootView()
}
