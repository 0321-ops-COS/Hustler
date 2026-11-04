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
    @Published var accountEmail = ""
    @Published var accountPassword = ""
    @Published private(set) var accountSummary: [StoreKeySummary] = []
    @Published private(set) var accountMessage: String?
    @Published private(set) var accountBusy = false
    @Published private(set) var isSignedIn = false
    /// True until the Keychain session has been read, so a signed-in user never
    /// sees the sign-in form flash before their account appears.
    @Published private(set) var isLoadingAccount = true

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

    /// Reads the stored session off the main actor. `SecItemCopyMatching` is a
    /// synchronous system call, so doing it in `init` — which the app shell can
    /// build for every tab — would stall the main view while it runs.
    func loadAccount() async {
        isLoadingAccount = true
        let signedIn = await Task.detached(priority: .userInitiated) {
            SupabaseAccount(storage: KeychainSessionStorage()).storedSession != nil
        }.value
        isSignedIn = signedIn
        isLoadingAccount = false
        if signedIn { await loadSummary() }
    }

    /// The read-only summary needs its own request, so it runs off the main
    /// actor too rather than parsing the response while the UI waits.
    private func loadSummary() async {
        do {
            accountSummary = try await Task.detached(priority: .userInitiated) {
                try await SupabaseAccount(storage: KeychainSessionStorage()).fetchSummary()
            }.value
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    /// The password stays in this field only: never saved, logged or put in a URL.
    /// Signing in, the Keychain write and the summary parse all run off the main
    /// actor, so the UI keeps drawing while the network answers.
    func signIn() {
        let email = accountEmail.trimmingCharacters(in: .whitespaces)
        guard !accountBusy, !email.isEmpty, !accountPassword.isEmpty else { return }
        let password = accountPassword
        accountBusy = true
        accountMessage = nil
        Task {
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    let account = SupabaseAccount(storage: KeychainSessionStorage())
                    try await account.signIn(email: email, password: password)
                    return try await account.fetchSummary()
                }.value
                accountPassword = ""
                isSignedIn = true
                accountSummary = summary
            } catch {
                accountMessage = error.localizedDescription
            }
            accountBusy = false
        }
    }

    func signOut() {
        isSignedIn = false
        accountSummary = []
        accountMessage = nil
        accountPassword = ""
        Task.detached(priority: .userInitiated) {
            SupabaseAccount(storage: KeychainSessionStorage()).signOut()
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
