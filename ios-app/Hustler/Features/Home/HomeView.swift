import SwiftUI
import HustlerCore

/// The Home screen: one decline-float card, then the way through to statements.
struct HomeView: View {

    @StateObject private var model = HomeViewModel()

    var body: some View {
        Form {
            Section {
                FloatCard(card: model.float)
            } footer: {
                Text("Counts declines among your last 100 offers. It moves when a newer acceptance rate is logged.")
            }

            Section("Earnings") {
                NavigationLink("Statement import") { StatementImportView() }
                Text("Monthly totals from a statement PDF or pasted text. Each month's total replaces that month's estimated archive pay, to the cent.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Not ported yet") {
                Text("Check and What-if, History, Earn, quests, the California guarantee, and the master-log editor beyond raw text.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Hustler")
    }
}

private struct FloatCard: View {
    let card: HomeFloat.Card

    private var color: Color {
        switch card.severity {
        case .calm: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title).font(.headline)
                Spacer()
                Text(card.value).font(.headline).monospacedDigit().foregroundStyle(color)
            }
            Text(card.message).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .listRowBackground(color.opacity(0.12))
    }
}

#Preview {
    NavigationStack { HomeView() }
}
