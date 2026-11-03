import SwiftUI
import HustlerCore

/// The web `#hist` page. Every tile, table row and bar is `HistoryPage`'s; this
/// file only lays them out.
struct HistoryView: View {
    @StateObject private var model = HistoryModel()

    var body: some View {
        Form {
            if let problem = model.problem {
                Section(HistoryCopy.title) { Text(problem).font(.footnote).foregroundStyle(.red) }
            } else if model.page.isEmpty {
                ContentUnavailableView {
                    Label(HistoryCopy.emptyTitle, systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(HistoryCopy.emptyHint)
                } actions: {
                    NavigationLink("Open Data page") { DataView() }
                }
            } else {
                pageBody
            }
        }
        .navigationTitle(HistoryCopy.title).navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reload() }
    }

    private var pageBody: some View {
        let page = model.page
        return Group {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(page.tiles, id: \.label) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.value).font(.headline).monospacedDigit()
                            Text(tile.label).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            ForEach(HistoryCopy.monthHeaders, id: \.self) { cell in
                                Text(cell).frame(minWidth: 92, alignment: .leading)
                            }
                        }.font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(page.months, id: \.key) { month in
                            GridRow {
                                Text(month.key)
                                Text("\(month.deliveries)")
                                Text(month.averagePickupToDrop)
                            }.font(.caption).monospacedDigit()
                        }
                    }
                }
            } header: { Text(HistoryCopy.monthTitle) }
            bars(HistoryCopy.hourTitle, page.hours)
            bars(HistoryCopy.dayTitle, page.weekdays)
            Section(HistoryCopy.storeTitle) {
                ForEach(page.stores, id: \.name) { store in
                    LabeledContent(store.name, value: "\(store.deliveries)")
                }
            }
            if page.duplicatesHidden > 0 {
                Section {
                    Text(HistoryCopy.duplicatesNote(page.duplicatesHidden))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bars(_ title: String, _ bars: [HistoryPage.Bar]) -> some View {
        Section(title) {
            ForEach(bars, id: \.label) { bar in
                HStack(spacing: 10) {
                    Text(bar.label).frame(width: 44, alignment: .leading)
                    ProgressView(value: bar.fractionOfMax)
                    Text("\(bar.deliveries)").monospacedDigit().frame(width: 34, alignment: .trailing)
                }.font(.caption)
            }
        }
    }
}

/// Thin adapter: re-reads the archive and the log, then hands both to
/// `HistoryViewModel.build`. It decides nothing the core does not.
@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var page = HistoryPage.empty
    @Published private(set) var problem: String?

    private let store: LocalStore

    init(store: LocalStore = LocalStore()) {
        self.store = store
        reload()
    }

    /// The duplicate rule reads the log as well as the archive, so both are read.
    func reload() {
        let library = LocalLibrary(store: store)
        if case let .unavailable(reason) = library.status(of: .archive) {
            problem = reason
            page = .empty
            return
        }

        problem = nil
        page = HistoryViewModel.build(
            archive: library.archive,
            logRows: MasterLogParser.parse(library.log.text)
        )
    }
}
