import SwiftUI
import HustlerCore

/// The web `#earn` page. Every label, value and note is `EarningsPage`'s; this
/// file only lays them out.
struct EarningsView: View {
    @StateObject private var model = EarningsViewModel()

    var body: some View {
        Form {
            if let problem = model.statementsProblem {
                Section(EarningsPage.title) { Text(problem).font(.footnote).foregroundStyle(.red) }
            } else if model.page.months.isEmpty {
                ContentUnavailableView {
                    Label("No statements yet", systemImage: "doc.text")
                } description: {
                    Text(EarningsPage.hint)
                } actions: {
                    NavigationLink("Open Data page") { DataView() }
                }
            } else {
                earnings
            }
        }
        .navigationTitle("Earnings").navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reload() }
    }

    private var earnings: some View {
        let page = model.page
        return Group {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(page.tiles) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.value).font(.headline).monospacedDigit()
                                .foregroundStyle(tile.isMoney ? Color.accentColor : Color.primary)
                            Text(tile.label).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            ForEach(Array(EarningsPage.monthHeaders.enumerated()), id: \.offset) { _, cell in
                                Text(cell).frame(minWidth: 62, alignment: .trailing)
                            }
                        }.font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(page.months) { row in
                            GridRow {
                                ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                                    Text(cell).frame(minWidth: 62, alignment: .trailing)
                                }
                            }.font(.caption).monospacedDigit()
                        }
                    }
                }
            } header: { Text(EarningsPage.monthsTitle) } footer: { Text(EarningsPage.monthHint) }
            Section(EarningsPage.daysTitle) {
                ForEach(page.days) { day in
                    HStack(spacing: 10) {
                        Text(day.day).frame(width: 36, alignment: .leading)
                        ProgressView(value: day.share)
                        Text("\(day.deliveries)").monospacedDigit().frame(width: 34, alignment: .trailing)
                    }.font(.caption)
                }
            }
            Section(EarningsPage.notesTitle) {
                ForEach(page.notes, id: \.self) { Text($0).font(.footnote) }
            }
        }
    }
}
