import SwiftUI
import HustlerCore

/// Home: the web Scoreboard's period block. All values are `HomePeriodBoard` /
/// `HomeTiles` results; this file only draws them.
struct HomeView: View {
    @StateObject private var model = HomeViewModel()

    var body: some View {
        Group {
            if let problem = model.logUnavailable {
                ContentUnavailableView {
                    Label("Master log unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(problem)
                } actions: {
                    Text("Open the Statements tab to keep a copy and start a new log.")
                        .font(.footnote)
                }
            } else if !model.hasLog {
                ContentUnavailableView {
                    Label("No master log yet", systemImage: "doc.text")
                } description: {
                    Text("Home totals come from the master log. Paste it, or import a DoorDash archive, in the Statements tab.")
                }
            } else {
                periods
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reload() }
    }

    private var periods: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $model.period) {
                ForEach(PeriodGrouping.Period.allCases, id: \.self) { period in
                    Text(period.rawValue.capitalized).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 12)

            if let card = model.floatCard {
                HomeFloatCard(card: card)
            }

            if let bucket = model.selectedBucket {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.label).font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(bucket.bigNetText)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                        Text("net").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(model.tiles) { tile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tile.value)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(tile.isMoney ? Color.accentColor : Color.primary)
                        Text(tile.label).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding([.horizontal, .top], 12)

            List {
                Section {
                    ForEach(model.buckets) { bucket in
                        let selected = bucket.key == model.selectedKey
                        Button { model.select(bucket.key) } label: {
                            HStack(spacing: 8) {
                                Text(bucket.label)
                                    .font(.caption.weight(selected ? .semibold : .regular))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(bucket.rowGrossText).frame(width: 56, alignment: .trailing)
                                Text(bucket.rowNetText).frame(width: 56, alignment: .trailing)
                                Text(bucket.takenText).frame(width: 38, alignment: .trailing)
                                Text(bucket.netPerHourText).frame(width: 56, alignment: .trailing)
                            }
                            .font(.caption)
                            .monospacedDigit()
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selected ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(model.tableHeader).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Gross").frame(width: 56, alignment: .trailing)
                        Text("Net").frame(width: 56, alignment: .trailing)
                        Text("Taken").frame(width: 38, alignment: .trailing)
                        Text("Net $/hr").frame(width: 56, alignment: .trailing)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            .listStyle(.plain)
        }
    }
}

/// The coloured decline-float card. Colour comes from `HomeFloat.Tone`; this
/// view only maps it to a `Color` and draws the text.
private struct HomeFloatCard: View {
    let card: HomeFloat.Card

    private var tint: Color {
        switch card.tone {
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(card.value)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            Text(card.message)
                .font(.footnote)
            Text(card.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.35)))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}
