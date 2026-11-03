import SwiftUI
import UIKit
import HustlerCore
struct LogView: View {
    @StateObject private var model = LogViewModel()
    @State private var confirmClear = false
    @State private var confirmEmpty = false
    var body: some View {
        Form {
            if let notice = model.page.notice {
                Text(notice).font(.footnote)
                    .foregroundStyle(model.page.noticeIsFailure ? Color.red : Color.secondary)
            }
            if let problem = model.page.problem {
                Section("Saved master log unavailable") {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                    Button("Keep a copy and start a new log") { model.update { model.page.recover() } }
                    Text("The saved log has not been changed. Saving stays blocked until you do this.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                scopeSection
                editorSection
                actionsSection
                if !model.page.columns.isEmpty { checkSection }
                if model.page.demoText != nil { demoSection }
            }
        }
        .navigationTitle("Master file")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove every row for this \(model.page.scopeWord)?", isPresented: $confirmEmpty) {
            Button("Remove", role: .destructive) { model.update { model.page.analyzeAndSave(confirmEmptyScope: true) } }
        }
        .confirmationDialog("Delete all entries for \(model.page.key ?? "this day")?", isPresented: $confirmClear) {
            Button("Delete", role: .destructive) { model.update { model.page.clearForToday(confirmed: true) } }
        }
    }
    private var scopeSection: some View {
        Section("Master file") {
            Picker("Scope", selection: Binding(get: { model.page.mode }, set: { m in model.update { model.page.setMode(m) } })) {
                ForEach(LogPageModel.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if model.page.isScoped {
                HStack {
                    Button { model.update { model.page.step(older: true) } } label: { Image(systemName: "chevron.left") }
                        .disabled(!model.page.canStepOlder)
                    Picker("Pick", selection: Binding(get: { model.page.key ?? "" }, set: { k in model.update { model.page.select(k) } })) {
                        ForEach(model.page.scopes, id: \.key) { Text($0.label).tag($0.key) }
                    }
                    .labelsHidden()
                    Button { model.update { model.page.step(older: false) } } label: { Image(systemName: "chevron.right") }
                        .disabled(!model.page.canStepNewer)
                }
            }
            Text(model.page.info).font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var editorSection: some View {
        Section(model.page.isScoped ? "Rows for this \(model.page.scopeWord)" : "Master log") {
            TextEditor(text: Binding(get: { model.page.draft }, set: { t in model.update { model.page.draft = t } }))
                .frame(minHeight: 220)
                .font(.system(.caption, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
    private var actionsSection: some View {
        Section {
            Button("Analyze and save") {
                if model.page.needsEmptyScopeConfirmation { confirmEmpty = true } else { model.update { model.page.analyzeAndSave() } }
            }
            Button(model.page.clearTitle) {
                if model.page.needsClearConfirmation { confirmClear = true } else { model.update { model.page.clearForToday() } }
            }
            Button("Try demo data (not saved)") { model.update { model.page.tryDemo() } }
            Button("Paste copied rows") { model.update { model.page.pasteRows(UIPasteboard.general.string ?? "") } }
        }
    }

    private var checkSection: some View {
        Section("Check") {
            ForEach(model.page.columns, id: \.name) { column in
                LabeledContent(column.name) {
                    Text("\(column.type) · \(column.check)")
                        .foregroundStyle(column.isClean ? Color.secondary : Color.red)
                }
            }
        }
    }
    private var demoSection: some View {
        Section {
            Text(model.page.demoText ?? "").font(.system(.caption2, design: .monospaced))
            Text("\(model.page.demoRows) invented rows. Demo data is never saved.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Demo — not saved") }
    }
}
/// Thin adapter: republishes `LogPageModel` and supplies today's date.
@MainActor
final class LogViewModel: ObservableObject {
    let page = LogPageModel(store: LocalStore(), today: LogViewModel.todayKey())
    func update(_ body: () -> Void) { objectWillChange.send(); body() }
    private static func todayKey() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
