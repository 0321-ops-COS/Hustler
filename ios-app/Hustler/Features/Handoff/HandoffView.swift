import SwiftUI
import UniformTypeIdentifiers
import UIKit
import HustlerCore
/// The web `#sync` Handoff card reduced to its three working buttons: export
/// through the share sheet, import through the file picker, and copy the AI
/// brief. Cloud sync and shortcut link-up cards are deliberately absent.
struct HandoffView: View {
    @StateObject private var model = HandoffModel()
    @State private var choosingFile = false

    var body: some View {
        Form {
            Section {
                if let url = model.exportURL {
                    ShareLink(item: url) { Label("Export handoff file", systemImage: "square.and.arrow.up") }
                }
                Button("Import file", systemImage: "square.and.arrow.down") { choosingFile = true }
                Button("Copy AI brief", systemImage: "doc.on.doc") { model.copyBrief() }
            } header: {
                Text("Handoff")
            } footer: {
                Text("One file holds your settings and log. Import merges the file's rows into your log and changes only the settings it carries. A file that cannot be read changes nothing.")
            }
            if let notice = model.notice {
                Section {
                    Text(notice.text).font(.footnote)
                        .foregroundStyle(notice.isFailure ? Color.red : Color.secondary)
                }
            }
        }
        .navigationTitle("Handoff").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json, .plainText]) { result in
            switch result {
            case let .success(url): model.importFile(at: url)
            case let .failure(error): model.reportFailure(error)
            }
        }
        .onAppear { model.prepareExport() }
    }
}
/// Screen state only: `HandoffFile` says what the file means and what an import
/// would write; `SettingsStore` and `LocalLibrary` decide what may be saved.
@MainActor
final class HandoffModel: ObservableObject {
    struct Notice: Equatable { let text: String; let isFailure: Bool }
    @Published private(set) var exportURL: URL?
    @Published private(set) var notice: Notice?
    private let store: LocalStore
    private let settingsStore: SettingsStore
    private var library: LocalLibrary

    init(store: LocalStore = LocalStore()) {
        self.store = store
        self.settingsStore = SettingsStore(store: store)
        self.library = LocalLibrary(store: store)
        if settingsStore.isUnavailable {
            notice = Notice(text: "Saved settings could not be read. Nothing has been replaced; fix them under Settings first.", isFailure: true)
        }
    }

    /// `ShareLink` needs a file URL before it is drawn, so the export is written
    /// on arrival and refreshed after an import.
    func prepareExport() {
        if settingsStore.isUnavailable {
            exportURL = nil
            return
        }
        do {
            let data = try HandoffFile.export(settings: settingsStore.settings, log: library.log.text)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hustle-handoff.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
            notice = Notice(text: "Could not build the handoff file.", isFailure: true)
        }
    }

    func importFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let file = HandoffFile.decode(data) else {
            notice = Notice(text: "That is not a Hustle handoff file. Nothing was changed.", isFailure: true)
            return
        }
        let plan = file.importPlan(currentSettings: settingsStore.settings, currentLog: library.log.text)
        let settingsChanged = plan.settings != settingsStore.settings
        do {
            if plan.log != library.log.text { try library.saveLog(plan.log) }
            if settingsChanged { try settingsStore.save(plan.settings) }
        } catch {
            library = LocalLibrary(store: store)
            notice = Notice(text: error.localizedDescription, isFailure: true)
            return
        }
        library = LocalLibrary(store: store)
        prepareExport()
        let rows = plan.rowsAdded == 1 ? "1 new row" : "\(plan.rowsAdded) new rows"
        notice = Notice(
            text: "Imported \(rows)" + (settingsChanged ? " and your settings." : "; settings unchanged."),
            isFailure: false
        )
    }

    /// `#cpBrief`: `AIBrief` builds the text; this only puts it on the
    /// clipboard and shows the web app's confirmation.
    func copyBrief() {
        if settingsStore.isUnavailable {
            notice = Notice(text: "Saved settings could not be read. Nothing has been replaced; fix them under Settings first.", isFailure: true)
            return
        }
        UIPasteboard.general.string = AIBrief.copyText(settings: settingsStore.settings, log: library.log.text)
        notice = Notice(text: "AI brief copied", isFailure: false)
    }

    func reportFailure(_ error: Error) {
        notice = Notice(text: error.localizedDescription, isFailure: true)
    }
}
