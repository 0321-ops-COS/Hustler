import SwiftUI
import UniformTypeIdentifiers
import HustlerCore

/// The first screen that reaches the statement pipeline: a PDF or pasted text in,
/// a stored monthly total out, and the month's allocation shown against the log.
struct StatementImportView: View {

    @StateObject private var model = StatementImportModel()
    @State private var choosingPDF = false

    var body: some View {
        Form {
            if let notice = model.notice {
                Section {
                    Text(notice.text)
                        .font(.footnote)
                        .foregroundStyle(notice.isFailure ? Color.red : Color.secondary)
                }
            }

            Section {
                Button {
                    choosingPDF = true
                } label: {
                    Label("Choose a statement PDF", systemImage: "doc.text")
                }
                Text("Page one only. Only the month, the total payouts and the payout count are read — no OCR, and nothing leaves the device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("From a PDF")
            }

            Section {
                TextEditor(text: $model.pasteDraft)
                    .frame(minHeight: 110)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Read pasted text") { model.importPaste() }
                    .disabled(model.pasteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Or paste the statement text")
            } footer: {
                Text("The fallback when a PDF has no readable text. It is parsed by the same rules as the PDF.")
            }

            Section {
                TextEditor(text: $model.logDraft)
                    .frame(minHeight: 110)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save master log") { model.saveLog() }
                LabeledContent("Rows", value: "\(model.logRowCount)")
                LabeledContent("Archive rows", value: "\(model.logArchiveRowCount)")
            } header: {
                Text("Master log")
            } footer: {
                Text("Reconciliation spreads each statement month's total over that month's archive rows by minutes, in whole cents, so the parts add up to the statement exactly. The log stays pipe-table text.")
            }

            Section("Statement months") {
                if model.summaries.isEmpty {
                    Text("No statement imported yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.summaries, id: \.month) { summary in
                        StatementMonthRow(summary: summary)
                    }
                }
            }
        }
        .navigationTitle("Statements")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choosingPDF, allowedContentTypes: [.pdf]) { result in
            switch result {
            case let .success(url):
                model.importPDF(at: url)
            case let .failure(error):
                model.reportFailure(error)
            }
        }
    }
}

private struct StatementMonthRow: View {
    let summary: StatementMonthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(StatementImportModel.monthLabel(summary.month))
                    .font(.headline)
                Spacer()
                Text(Money.format(summary.total))
                    .font(.headline)
                    .monospacedDigit()
            }

            Text("\(summary.payouts) payouts · \(summary.archiveRows) archive rows · \(summary.loggedRows) logged")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if summary.archiveRows > 0 {
                Text("Allocated \(Money.format(summary.allocatedPay)) across those archive rows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No archive rows in this month, so nothing could be re-priced yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if summary.loggedLivePay > 0 {
                Text("Includes \(Money.format(summary.loggedLivePay)) of logged live pay on top of the statement total. That over-count is how the web app behaves today (known defect B1), preserved here on purpose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        StatementImportView()
    }
}
