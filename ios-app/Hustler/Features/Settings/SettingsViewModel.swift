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

    // Account (read-only): the session is Keychain-backed, never stored values.
    @Published private(set) var accountSummary: [StoreKeySummary] = []
    @Published private(set) var accountMessage: String?
    @Published private(set) var isSignedIn = false

    // Pull from account: read-only, and nothing is written until the import tap.
    @Published private(set) var pullPreview: [AccountDataSet] = []
    @Published private(set) var pullMessage: String?
    @Published private(set) var pullBusy = false
    @Published private(set) var pullCanImport = false
    private var pendingPull: AccountPullPlan?

    private let account = SupabaseAccount(storage: KeychainSessionStorage())
    private let store: LocalStore
    private let settingsStore: SettingsStore

    init(store: LocalStore = LocalStore()) {
        self.store = store
        let loaded = SettingsStore(store: store)
        settingsStore = loaded
        edit = SettingsEdit(loaded.settings)
        texts = Self.texts(for: loaded.settings)
        isSignedIn = account.storedSession != nil
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

    /// Loads the account summary; the call refreshes an expiring token first.
    /// `false` means the session is gone (a rejected refresh cleared it), so the
    /// shell returns to the gate. A network failure keeps the session and says
    /// so instead.
    @discardableResult
    func loadAccount() async -> Bool {
        isSignedIn = account.storedSession != nil
        guard isSignedIn else { return false }
        do {
            accountSummary = try await account.fetchSummary()
        } catch {
            accountMessage = error.localizedDescription
        }
        isSignedIn = account.storedSession != nil
        return isSignedIn
    }

    /// Clears the sign-in on this device only. No log entry, archive row or
    /// setting is deleted.
    func signOut() {
        account.signOut()
        isSignedIn = false
        accountSummary = []
        accountMessage = nil
        pullPreview = []
        pullMessage = nil
        pullCanImport = false
        pendingPull = nil
    }

    /// The preview: what the account holds against what this phone holds, per
    /// data set, plus how old the account's copy is. Nothing is written here.
    func previewAccountPull() async {
        guard !pullBusy else { return }
        pullBusy = true
        pullMessage = nil
        pullPreview = []
        pullCanImport = false
        pendingPull = nil
        defer { pullBusy = false }

        do {
            let rows = try await account.fetchRows()
            let library = LocalLibrary(store: store)
            pullPreview = AccountPull.preview(rows: rows, currentSettings: settingsStore.settings,
                                              currentLog: library.log.text)
            let plan = try AccountPull.plan(rows: rows, currentSettings: settingsStore.settings,
                                            currentLog: library.log.text)
            pendingPull = plan
            pullCanImport = true
            pullMessage = "Account: \(plan.accountRows) log rows. This phone: \(plan.phoneRows)."
        } catch {
            pullMessage = error.localizedDescription
        }
    }

    /// The only write, and only on an explicit tap. The phone's current data is
    /// saved as a handoff file first, then replaced by the account's settings
    /// and log. The archive, statements and CA weeks are not imported yet.
    func importFromAccount() async {
        guard let plan = pendingPull, !pullBusy else { return }
        pullBusy = true
        pullMessage = nil
        defer { pullBusy = false }

        do {
            let library = LocalLibrary(store: store)
            let backup = try AccountPullBackup.write(settings: settingsStore.settings,
                                                     log: library.log.text,
                                                     into: store.directory)
            if plan.logChanged { try library.saveLog(plan.log) }
            if plan.settingsChanged { try settingsStore.save(plan.settings) }
            pendingPull = nil
            pullCanImport = false
            reload()
            pullMessage = "Replaced with your account's data. A copy of this phone's data was saved as "
                + "\(backup.lastPathComponent) in the app's \(store.directory.lastPathComponent) folder."
        } catch {
            pullMessage = error.localizedDescription
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
