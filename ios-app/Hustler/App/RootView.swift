import SwiftUI
import HustlerCore

/// Milestone 0 shell. It exists to prove the app target builds and can link
/// `HustlerCore`; it deliberately contains no offer analysis, history, earnings
/// or California logic.
struct RootView: View {
    @State private var payoutText: String = ""

    private var payout: Double { Money.parse(payoutText) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Milestone 0") {
                    Text("Native foundation builds and links HustlerCore.")
                    Text("No earnings logic is ported yet. Open defect B1 remains documented and unresolved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Formatting check") {
                    TextField("Payout, e.g. 12.50", text: $payoutText)
                        .keyboardType(.decimalPad)
                    LabeledContent("Formatted", value: Money.format(payout))
                }
            }
            .navigationTitle("Hustler")
        }
    }
}

#Preview {
    RootView()
}
