import Foundation
import Combine
import HustlerCore

/// Settings-tab state. Parsing and rejection are `SettingsEdit`'s; this class
/// only loads, holds the text boxes and writes the file.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var edit: SettingsEdit
    @Published private(set) var texts: [SettingsField: String]
    @Published private(set) var message: String?

    private let settingsStore: SettingsStore

    init(store: LocalStore = LocalStore()) {
        let loaded = SettingsStore(store: store)
        settingsStore = loaded
        edit = SettingsEdit(loaded.settings)
        texts = Self.texts(for: loaded.settings)
        if case let .unavailable(reason) = loaded.status { message = reason }
    }

    var fields: [SettingsField] { SettingsField.all }
    var pages: [AppPage] { AppPage.all }
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
