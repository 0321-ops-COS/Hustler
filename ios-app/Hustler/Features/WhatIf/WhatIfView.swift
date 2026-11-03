import SwiftUI
import HustlerCore

/// The web `#whatif` section: one field per setting, "Replay my log", and the
/// result cards. Every number and caption comes from `WhatIf`; nothing is saved.
struct WhatIfView: View {
    @StateObject private var model = WhatIfViewModel()

    var body: some View {
        Form {
            Section {
                Text(model.blurb).font(.footnote).foregroundStyle(.secondary)
                ForEach(WhatIf.Field.all) { field in
                    LabeledContent(field.label) {
                        TextField(field.label, text: Binding(
                            get: { model.text(for: field) },
                            set: { model.setText($0, for: field) }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }
                }
                Button("Replay my log") { model.run() }
            } header: {
                Text("What-if")
            }

            if let replay = model.replay {
                if replay.hasRows { results(replay) } else {
                    Section { Text(WhatIf.emptyLogMessage).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("What-if")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func results(_ replay: WhatIf.Replay) -> some View {
        Section {
            Text(replay.acceptanceLine).font(.footnote).foregroundStyle(.secondary)
            ForEach(replay.tableRows, id: \.label) { row in
                LabeledContent(row.label) {
                    HStack(spacing: 16) {
                        Text(row.currentText)
                        Text(row.changedText).fontWeight(.semibold)
                    }
                }
            }
            Text(replay.summaryLine)
                .font(.headline)
                .foregroundStyle(replay.isGain ? .green : .red)
        } header: {
            Text(WhatIf.resultsTitle)
        } footer: {
            Text("Current / Your change")
        }

        if !replay.flipped.isEmpty {
            Section {
                ForEach(Array(replay.flipped.enumerated()), id: \.offset) { _, flip in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flip.offer)
                        HStack(spacing: 12) {
                            Text(flip.payout).fontWeight(.medium)
                            Text(flip.miles).foregroundStyle(.secondary)
                            Text(flip.currentText).foregroundStyle(.secondary)
                            Text("→")
                            Text(flip.changedText)
                                .foregroundStyle(flip.changedTook ? .green : .red)
                        }
                        .font(.caption)
                    }
                }
            } header: {
                Text(WhatIf.flippedTitle)
            } footer: {
                Text("Offer, payout, miles, then the verdict now and under your change.")
            }
        }
    }
}

/// What-if-tab state. `WhatIf` owns the replay; this class only reads the stored
/// log and settings, holds the boxes and reads them with the web app's `num()`.
@MainActor
final class WhatIfViewModel: ObservableObject {
    @Published private(set) var texts: [WhatIf.Field: String]
    @Published private(set) var replay: WhatIf.Replay?

    let blurb = "Change a number, then replay your whole log with the shortcut rule: "
        + "an offer needs to beat the $/mile and $/hour bars, which slide from base to "
        + "floor between the ramp low and ramp top acceptance rates. Changes here are not saved."

    private let rows: [LogRow]
    private let settings: AppSettings

    init(store: LocalStore = LocalStore()) {
        let stored = SettingsStore(store: store).settings
        settings = stored
        rows = MasterLog.orderedForAnalysis(
            MasterLogParser.parse(LocalLibrary(store: store).log.text)
        )
        texts = Dictionary(uniqueKeysWithValues: WhatIf.Field.all.map { ($0, $0.text(in: stored)) })
    }

    func text(for field: WhatIf.Field) -> String { texts[field] ?? "" }

    func setText(_ text: String, for field: WhatIf.Field) { texts[field] = text }

    /// `draft()` plus the `#runWf` handler: every box is read with `num()`, so a
    /// blank or unreadable box becomes 0, and the stored settings are untouched.
    func run() {
        var change = settings
        for field in WhatIf.Field.all {
            field.set(Money.parse(texts[field] ?? ""), in: &change)
        }
        replay = WhatIf.replay(rows: rows, settings: settings, change: change)
    }
}
