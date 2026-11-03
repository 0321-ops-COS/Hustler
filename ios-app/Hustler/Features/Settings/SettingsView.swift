import SwiftUI
import HustlerCore

/// The web `#settings` section: shortcut card, numeric fields and Pages card.
/// Values and validation come from `SettingsEdit`; this file only lays them out.
struct SettingsView: View {
    /// Lets the shell redraw the tab bar as soon as a pin is switched.
    var onPinsChanged: () -> Void = {}

    @StateObject private var model = SettingsViewModel()
    @Environment(\.openURL) private var openURL
    @State private var confirmingRebuild = false

    var body: some View {
        Form {
            Section("Account") {
                if model.isSignedIn {
                    Button("Sign out") { model.signOut() }
                    ForEach(model.accountSummary) { item in
                        HStack {
                            Text(item.key)
                            Spacer()
                            Text(item.line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    TextField("Email", text: $model.accountEmail)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $model.accountPassword)
                    Button("Sign in") { model.signIn() }
                        .disabled(model.accountBusy || model.accountEmail.isEmpty || model.accountPassword.isEmpty)
                }
                if let message = model.accountMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Shortcut") {
                Button("Run the offer analyzer") {
                    if let url = model.runShortcutURL { openURL(url) }
                }
                .disabled(model.runShortcutURL == nil)
                Button("Get the shortcut") {
                    if let url = model.shortcutLinkURL { openURL(url) }
                }
                .disabled(model.shortcutLinkURL == nil)
            }

            ForEach(SettingsField.Group.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(model.fields.filter { $0.group == group }) { field in
                        numberField(field)
                    }
                }
            }

            archiveRebuild
            pages
            if let message = model.message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Save") { model.save() } }
        .onAppear { model.refreshArchive() }
        .confirmationDialog(
            ArchiveRebuildCopy.confirmation,
            isPresented: $confirmingRebuild,
            titleVisibility: .visible
        ) {
            Button(ArchiveRebuildCopy.button) { model.rebuildArchive() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var archiveRebuild: some View {
        Section {
            Button(ArchiveRebuildCopy.button) {
                if model.hasSavedArchive { confirmingRebuild = true } else { model.reportMissingArchive() }
            }
            if let message = model.archiveMessage {
                Text(message).font(.footnote)
                    .foregroundStyle(model.archiveMessageIsFailure ? Color.red : Color.secondary)
            }
        } header: {
            Text(ArchiveRebuildCopy.title)
        } footer: {
            Text(ArchiveRebuildCopy.hint)
        }
    }

    private func numberField(_ field: SettingsField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(field.label) {
                TextField(field.label, text: Binding(
                    get: { model.text(for: field) },
                    set: { model.setText($0, for: field) }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            }
            if let note = model.note(for: field) {
                Text(note).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var pages: some View {
        Section {
            ForEach(model.pages) { page in
                HStack {
                    NavigationLink {
                        AppScreenView(screen: page.screen)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(page.title)
                            Text(page.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Show \(page.title) in menu", isOn: Binding(
                        get: { model.isPinned(page) },
                        set: {
                            model.setPinned(page, $0)
                            onPinsChanged()
                        }
                    ))
                    .labelsHidden()
                }
            }
        } header: {
            Text("Pages")
        } footer: {
            Text("Tap a bar to open that page. Use its switch to add or remove it from the menu.")
        }
    }
}

/// The screen for a page that has no view yet. Every `PGS` page is built, so
/// nothing currently lands here, but a new page can without a dead link.
struct ComingSoonView: View {
    let title: String

    var body: some View {
        ContentUnavailableView("Coming soon", systemImage: "hammer", description: Text(title))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
