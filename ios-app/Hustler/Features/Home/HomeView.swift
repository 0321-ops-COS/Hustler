import SwiftUI
import HustlerCore

/// Home: one period at a time, newest first, read from the stored master log.
/// Everything is computed in `HomeViewModel`; this file only draws it.
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
                periodsAndList
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reload() }
    }

    private var periodsAndList: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $model.period) {
                ForEach(PeriodGrouping.Period.allCases, id: \.self) { period in
                    Text(period.rawValue.capitalized).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let card = model.floatCard {
                HomeFloatCard(card: card)
            }

            List(model.buckets) { bucket in
                HomeBucketRow(bucket: bucket)
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

private struct HomeBucketRow: View {
    let bucket: HomeViewModel.Bucket

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.label)
                    .font(.headline)
                if bucket.isCurrent {
                    Text("Now")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.format(bucket.totals.net))
                    .font(.headline)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Text("Gross \(Money.format(bucket.totals.gross))")
                Text("\(bucket.offers) offers")
                Text(bucket.hoursText)
                Text("\(bucket.netPerHourText)/hr")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
