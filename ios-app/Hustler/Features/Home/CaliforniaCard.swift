import SwiftUI
import HustlerCore

/// The California pay guarantee, after the period table as `#ca` is in the web
/// app. Every label, value and hint is `CAGuaranteeViewModel`'s; this file lays
/// them out and forwards the slider and the entry sheet to the view model.
struct CaliforniaCardView: View {
    @ObservedObject var model: HomeViewModel
    @State private var entering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CAGuaranteeViewModel.heading).font(.subheadline.weight(.semibold))
            if let card = model.caCard {
                content(card)
            } else {
                Text("The saved log could not be read, so this card is hidden until it is repaired.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $entering) { CAEntrySheet(model: model) }
    }

    @ViewBuilder
    private func content(_ card: CAGuaranteeViewModel) -> some View {
        Text(card.headerHint).font(.caption).foregroundStyle(.secondary)

        if card.isNotEnoughData {
            Text(CAGuaranteeViewModel.notEnoughDataTitle).font(.headline)
            Text(CAGuaranteeViewModel.notEnoughDataHint).font(.caption).foregroundStyle(.secondary)
        } else {
            Text(CAGuaranteeViewModel.disclaimer).font(.caption2).foregroundStyle(.secondary)
            table(card)
            Text(card.offersHint).font(.caption2).foregroundStyle(.secondary)
            Text(card.paceHint).font(.caption2).foregroundStyle(.secondary)
            if card.pace != nil, card.maxExtraHours > 0 {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(card.extraHours) },
                            set: { model.setCAExtraHours(Int($0.rounded())) }
                        ),
                        in: 0...Double(card.maxExtraHours),
                        step: 1
                    )
                    Text(card.sliderLabel)
                        .font(.caption)
                        .monospacedDigit()
                        .frame(minWidth: 52, alignment: .trailing)
                }
            }
            ForEach(card.equationLines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }

        Button("Enter or clear this week") {
            model.beginCAEntry()
            entering = true
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func table(_ card: CAGuaranteeViewModel) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            GridRow {
                Text(CAGuaranteeViewModel.tableHeaders[0])
                ForEach(1..<CAGuaranteeViewModel.tableHeaders.count, id: \.self) { index in
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(CAGuaranteeViewModel.tableHeaders[index])
                        Text(CAGuaranteeViewModel.tableSubheaders[index])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.caption2.weight(.semibold))

            ForEach(Array(card.tableRows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    Text(row.label)
                    Text(row.soFar).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(row.added).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(row.total).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(index == card.tableRows.count - 1 ? .caption.weight(.semibold) : .caption)
                .monospacedDigit()
            }
        }
    }
}

/// Three text fields for one week; `CAEntryDraft` parses and stores them, and the
/// core decides what a blank field or a clear means. The sheet only dismisses on
/// a write that succeeded.
private struct CAEntrySheet: View {
    @ObservedObject var model: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Pay ($)", text: $model.caDraft.pay)
                    field("Active hours", text: $model.caDraft.hours)
                    field("Miles", text: $model.caDraft.miles)
                    if let error = model.caError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text(model.caCard?.headerHint ?? model.caWeekKey)
                } footer: {
                    Text("A blank field leaves that figure to the log. Saving all three blank, or Clear, removes this week's entry.")
                }

                Section {
                    Button("Save this week") {
                        if model.saveCAEntry() { dismiss() }
                    }
                    Button("Clear this week", role: .destructive) {
                        if model.clearCAWeek() { dismiss() }
                    }
                }
            }
            .navigationTitle("California entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}
