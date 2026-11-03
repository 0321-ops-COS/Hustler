import SwiftUI
import HustlerCore

/// The web `#calc` section: six fields, the log-rate helper and the verdict
/// card. Every number comes from `CheckModel`.
struct CheckView: View {
    @StateObject private var model = CheckViewModel()

    private let fields: [(CheckModel.Field, String)] = [
        (.payout, "Payout ($)"), (.miles, "Miles"), (.items, "Items"),
        (.minutes, "Minutes (blank = shortcut formula)"), (.gasToday, "Gas today ($/gal)"),
        (.rate, "Acceptance rate (%)")
    ]

    var body: some View {
        Form {
            Section {
                ForEach(fields, id: \.0) { field, label in
                    LabeledContent(label) {
                        TextField(label, text: binding(field))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                Text("Same rule as the log replay, using your saved settings.")
            }
            if let hint = model.logRateHint {
                HStack {
                    Text(hint)
                    Spacer()
                    Button("Use it") { model.useLogRate() }.buttonStyle(.bordered)
                }
            }
            Section {
                Button("Get verdict") { model.getVerdict() }.frame(maxWidth: .infinity)
            }
            if let outcome = model.outcome { result(outcome) }
            if let message = model.message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(_ field: CheckModel.Field) -> Binding<String> {
        Binding(get: { model.text(for: field) }, set: { model.setText($0, for: field) })
    }

    @ViewBuilder
    private func result(_ outcome: CheckModel.Outcome) -> some View {
        switch outcome {
        case .needsPayoutAndMiles:
            Section { Text("Enter payout and miles").foregroundStyle(.secondary) }
        case let .verdict(verdict):
            Section {
                Text(verdict.headline)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(verdict.result.takeIt ? .green : .red)
                    .frame(maxWidth: .infinity)
                ForEach(verdict.stats) { stat in
                    LabeledContent(stat.label, value: stat.value)
                }
            }
        }
    }
}
