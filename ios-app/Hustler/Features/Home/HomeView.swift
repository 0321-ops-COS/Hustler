import SwiftUI
import Combine
import HustlerCore

/// Home: the web Scoreboard's period block. All values are `HomePeriodBoard` /
/// `HomeTiles` results; this file only draws them.
struct HomeView: View {
    /// Both cards' buttons, and the master tile's Edit, open the Data tab,
    /// which is where imports and the master-file link live.
    var onOpenData: () -> Void = {}
    /// The gate's sentence about the pull after sign-in; nil when there is
    /// nothing to say.
    var accountNote: String? = nil

    @StateObject private var model = HomeViewModel()
    @StateObject private var analytics = AnalyticsViewModel()

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading this phone's data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        // The read and the parse run off the main thread, so this frame is drawn
        // before any file is opened.
        .task { await loadAll() }
        // A pull at sign-in, or an import on another tab, writes new files.
        .onReceive(NotificationCenter.default.publisher(for: .hustlerStoreDidChange)) { _ in
            Task { await loadAll() }
        }
    }

    private func loadAll() async {
        let snapshot = await model.load()
        analytics.apply(snapshot)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if let card = model.startCard {
                HomeStartCardView(card: card, onOpen: onOpenData)
            }
            if let card = model.masterCard {
                HomeMasterTileView(card: card, onOpen: onOpenData)
            }
            if let note = accountNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            Group {
                if let problem = model.logUnavailable {
                    ContentUnavailableView {
                        Label("Master log unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(problem)
                    } actions: {
                        Text("Open the Data tab to keep a copy and start a new log.")
                            .font(.footnote)
                    }
                } else if !model.hasLog {
                    VStack(spacing: 0) {
                        ContentUnavailableView {
                            Label("No master log yet", systemImage: "doc.text")
                        } description: {
                            Text("Home totals come from the master log. Paste it, or import a DoorDash archive, in the Data tab.")
                        }
                        CaliforniaCardView(model: model)
                            .padding(.horizontal)
                    }
                } else {
                    periods
                }
            }
        }
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

            if let card = model.questCard {
                QuestsCardView(card: card)
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

            if let card = model.followCard {
                HomeFollowCardView(card: card)
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

            if let note = model.followCard?.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

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

                Section {
                    CaliforniaCardView(model: model)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }

                AnalyticsPanels(model: analytics)
            }
            .listStyle(.plain)
        }
    }
}

/// The "Start here" checklist. Every title, detail and done state comes from
/// `HomeStartCard`; this view only picks icons and layout.
private struct HomeStartCardView: View {
    let card: HomeStartCard.Card
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title).font(.subheadline.weight(.semibold))
            if let lead = card.lead {
                Text(lead).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(card.steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(step.isDone ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.title).font(.caption)
                        Text(step.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !step.action.isEmpty {
                        Button(step.action, action: onOpen)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            }
            if let note = card.note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

/// The master-file tile. The count and newest row are `HomeMasterTile`'s.
private struct HomeMasterTileView: View {
    let card: HomeMasterTile.Card
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title).font(.subheadline.weight(.semibold))
                Text(card.text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Edit", action: onOpen)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

/// This week's quests. Every string, state and progress value is
/// `Quests.Card`'s; this view only draws them.
private struct QuestsCardView: View {
    let card: Quests.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title).font(.subheadline.weight(.semibold))
            Text(card.summary).font(.caption2).foregroundStyle(.secondary)

            ForEach(card.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if case .tracked(true) = row.state {
                            Image(systemName: "checkmark").font(.caption2).foregroundStyle(.green)
                        }
                        Text(row.name).font(.caption)
                        Text(row.kind.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .background(.quaternary, in: Capsule())
                        Spacer(minLength: 2)
                        Text(row.valueText).font(.caption.weight(.semibold)).monospacedDigit()
                    }
                    if let hint = row.hint {
                        Text(hint).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let progress = row.progress {
                        ProgressView(value: progress)
                    }
                }
            }

            HStack {
                Text(card.lifetimeLabel).font(.caption)
                Spacer(minLength: 2)
                Text(card.lifetimeText).font(.caption.weight(.semibold)).monospacedDigit()
            }
            ProgressView(value: card.lifetimeProgress)
            Text(card.footer).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

/// The "Followed the call" ring. The percent, sentence and ring fill are
/// `HomeFollowCard.Card`'s; this view only strokes the ring.
private struct HomeFollowCardView: View {
    let card: HomeFollowCard.Card

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().strokeBorder(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: card.ringFill)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(card.percentText)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                Text(HomeFollowCard.title).font(.subheadline.weight(.semibold))
                Text(card.text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
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
