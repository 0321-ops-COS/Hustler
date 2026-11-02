import SwiftUI
import HustlerCore

/// The web Scoreboard's analytics, drawn below the period table. Every label,
/// value and hint is `AnalyticsViewModel`'s; this view only lays them out.
struct AnalyticsPanels: View {
    @ObservedObject var model: AnalyticsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            panel("Verdict vs. what you did") { matrix }
            panel("Zones that pay") {
                table(labelHeader: "Zone", columns: ["Orders", "Net $/hr", "Net $/mi"],
                      rows: model.zoneRows, hint: model.zoneHint)
            }
            panel("By month") {
                table(labelHeader: "Month", columns: ["Orders", "Gross", "Miles", "Net", "Mileage deduction"],
                      rows: model.monthRows, hint: model.monthHint)
            }
            panel("Best hours") {
                table(labelHeader: "Hour", columns: ["Orders", "Net $/hr"],
                      rows: model.hourRows, hint: model.hourHint)
            }
            panel("Tax summary") {
                table(labelHeader: "", columns: [], rows: model.taxRows, hint: "")
                Text(model.taxHint).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var matrix: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Verdict / you").frame(minWidth: 150, alignment: .leading)
                    Text("Offers").frame(minWidth: 52, alignment: .trailing)
                    Text("Net $/hr").frame(minWidth: 60, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(model.matrixRows) { row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(row.agrees ? Color.green : Color.red)
                            .frame(minWidth: 150, alignment: .leading)
                        Text(row.orders).frame(minWidth: 52, alignment: .trailing)
                        Text(row.netPerHour).frame(minWidth: 60, alignment: .trailing)
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func table(
        labelHeader: String,
        columns: [String],
        rows: [AnalyticsViewModel.Row],
        hint: String
    ) -> some View {
        if rows.isEmpty {
            Text(hint).font(.caption).foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                    if !columns.isEmpty {
                        GridRow {
                            Text(labelHeader).frame(minWidth: 90, alignment: .leading)
                            ForEach(columns, id: \.self) { name in
                                Text(name).frame(minWidth: 56, alignment: .trailing)
                            }
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.label).frame(minWidth: 90, alignment: .leading)
                            ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                                Text(value).frame(minWidth: 56, alignment: .trailing)
                            }
                        }
                        .font(.caption)
                        .monospacedDigit()
                    }
                }
            }
        }
    }
}
