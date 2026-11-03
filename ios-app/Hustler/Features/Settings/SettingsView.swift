import SwiftUI
import HustlerCore

/// The web `#settings` section: shortcut card, numeric fields and Pages card.
/// Values and validation come from `SettingsEdit`; this file only lays them out.
struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
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

            pages
            if let message = model.message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Save") { model.save() } }
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
                        if page.id == AppPage.earn.id {
                            EarningsView()
                        } else if page.id == AppPage.data.id {
                            DataView()
                        } else if page.id == AppPage.sync.id {
                            HandoffView()
                        } else {
                            ComingSoonView(title: page.title)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(page.title)
                            Text(page.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Show \(page.title) in menu", isOn: Binding(
                        get: { model.isPinned(page) },
                        set: { model.setPinned(page, $0) }
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

/// No page in the Pages card is built yet, so every bar lands here.
struct ComingSoonView: View {
    let title: String

    var body: some View {
        ContentUnavailableView("Coming soon", systemImage: "hammer", description: Text(title))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
