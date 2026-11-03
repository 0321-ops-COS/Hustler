import Foundation
import Combine
import HustlerCore
import HustlerArchive

/// Settings-tab state. Parsing and rejection are `SettingsEdit`'s; the archive
/// rebuild is `ArchiveImporter` + `ArchiveRebuild`'s; this class only loads,
/// holds the text boxes and writes the files.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var edit: SettingsEdit
    @Published private(set) var texts: [SettingsField: String]
    @Published private(set) var message: String?
    @Published private(set) var hasSavedArchive = false
    @Published private(set) var archiveMessage: String?
    @Published private(set) var archiveMessageIsFailure = false

    private let store: LocalStore
    private let settingsStore: SettingsStore

    init(store: LocalStore = LocalStore()) {
        self.store = store
        let loaded = SettingsStore(store: store)
        settingsStore = loaded
        edit = SettingsEdit(loaded.settings)
        texts = Self.texts(for: loaded.settings)
        if case let .unavailable(reason) = loaded.status { message = reason }
    }

    var fields: [SettingsField] { SettingsField.all }
    var pages: [AppPage] { AppPage.all }

    /// Re-reads the archive so the rebuild card reflects a Data-page import.
    func refreshArchive() {
        let library = LocalLibrary(store: store)
        hasSavedArchive = !library.archive.isEmpty && !library.isUnavailable(.archive)
    }

    func reportMissingArchive() {
        archiveMessage = ArchiveRebuild.Failure.missingArchive.errorDescription
        archiveMessageIsFailure = true
    }

    /// The web app's `#rebuildArch` through `LocalLibrary`: archive rows are
    /// rebuilt from the saved archive, every other row is kept, and the log is
    /// adopted only after the write succeeded. A blocked master log refuses it.
    func rebuildArchive() {
        let library = LocalLibrary(store: store)
        if case let .unavailable(reason) = library.status(of: .archive) {
            archiveMessage = reason
            archiveMessageIsFailure = true
            return
        }

        do {
            let outcome = try ArchiveImporter.rebuild(log: library.log.text, archive: library.archive)
            try library.saveLog(outcome.log)
            archiveMessage = outcome.message
            archiveMessageIsFailure = false
            refreshArchive()
        } catch {
            archiveMessage = error.localizedDescription
            archiveMessageIsFailure = true
        }
    }
    var runShortcutURL: URL? { edit.runShortcutURL }
    var shortcutLinkURL: URL? { edit.shortcutLinkURL }

    func text(for field: SettingsField) -> String { texts[field] ?? edit.text(for: field) }
    func note(for field: SettingsField) -> String? { edit.messages[field] }
    func isPinned(_ page: AppPage) -> Bool { edit.isPinned(page) }

    func setText(_ text: String, for field: SettingsField) {
        texts[field] = text
        edit.apply(text, to: field)
    }

    /// Pins persist on the tap; a refused write puts the switches back.
    func setPinned(_ page: AppPage, _ on: Bool) {
        edit.setPinned(page, on)
        if !save() { reload() }
    }

    @discardableResult
    func save() -> Bool {
        do {
            try settingsStore.save(edit.settings)
            message = "Settings saved"
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func reload() {
        edit = SettingsEdit(settingsStore.settings)
        texts = Self.texts(for: settingsStore.settings)
    }


    private static func texts(for settings: AppSettings) -> [SettingsField: String] {
        let edit = SettingsEdit(settings)
        return Dictionary(uniqueKeysWithValues: SettingsField.all.map { ($0, edit.text(for: $0)) })
    }
}
