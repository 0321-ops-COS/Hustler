import SwiftUI
import UniformTypeIdentifiers
import HustlerCore

/// The web `#data` section: imports via `StatementImportModel`, deletes via
/// `DataWipe`. This file lays their results out.
struct DataView: View {
    @StateObject private var imports = StatementImportModel()
    @StateObject private var deletes = DataDeleteModel()
    @State private var choosingPDF = false
    @State private var choosingArchive = false
    @State private var choosingOffers = false
    @State private var pending: DataDeleteAction?

    var body: some View {
        Form {
            Section(DataPageCopy.introTitle) { Text(DataPageCopy.intro) }
            card(DataPageCopy.offersTitle, DataPageCopy.offersHint) {
                Button("Choose an offers file", systemImage: "square.and.arrow.down") { choosingOffers = true }
            }
            card(DataPageCopy.statementsTitle, DataPageCopy.statementsHint) {
                Button("Choose a statement PDF", systemImage: "doc.text") { choosingPDF = true }
                TextEditor(text: $imports.pasteDraft).frame(minHeight: 70).font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Read pasted text") { imports.importPaste() }
                    .disabled(imports.pasteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            card(DataPageCopy.archiveTitle, DataPageCopy.archiveHint) {
                Button("Choose data_archive.zip", systemImage: "shippingbox") { choosingArchive = true }
                    .disabled(imports.isImportingArchive)
                if imports.isImportingArchive { ProgressView("Reading the archive…") }
            }
            Section {
                LabeledContent("Rows", value: "\(imports.logRowCount)")
                NavigationLink("Open and edit master file") { LogView() }
            } header: { Text("Master file") } footer: { Text(DataPageCopy.masterHint) }
            Section {
                ForEach(DataDeleteAction.allCases) { action in
                    Button(action.title, role: .destructive) { pending = action }
                }
            } header: { Text(DataPageCopy.deleteTitle) } footer: { Text(DataPageCopy.deleteHint) }
            if !deletes.blocked.isEmpty { blockedSection }
            if let notice = deletes.notice {
                Section { Text(notice).font(.footnote).foregroundStyle(deletes.noticeIsFailure ? Color.red : Color.secondary) }
            }
        }
        .navigationTitle("Data").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choosingPDF, allowedContentTypes: [.pdf]) { result in
            switch result {
            case let .success(url): imports.importPDF(at: url)
            case let .failure(error): imports.reportFailure(error)
            }
        }
        .fileImporter(isPresented: $choosingArchive, allowedContentTypes: [.zip]) { result in
            switch result {
            case let .success(url): imports.importArchive(at: url)
            case let .failure(error): imports.reportFailure(error)
            }
        }
        .fileImporter(isPresented: $choosingOffers, allowedContentTypes: [.commaSeparatedText, .plainText, .json]) { result in
            switch result {
            case let .success(url): imports.importOffers(at: url)
            case let .failure(error): imports.reportFailure(error)
            }
        }
        .confirmationDialog(pending?.confirmation ?? "", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible
        ) {
            if let action = pending {
                Button(action.title, role: .destructive) {
                    deletes.perform(action)
                    imports.reload()
                    pending = nil
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }

    private func card<Content: View>(_ title: String, _ hint: String, @ViewBuilder content: () -> Content) -> some View {
        Section { content() } header: { Text(title) } footer: { Text(hint) }
    }

    /// The Statements tab's recovery, offered here before any delete: the file is
    /// moved aside, never deleted, so a blocked artefact cannot be wiped.
    private var blockedSection: some View {
        Section("Saved data unavailable") {
            ForEach(deletes.blockedList, id: \.self) { artefact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(artefact.label).font(.headline)
                    Text(deletes.blocked[artefact] ?? "").font(.footnote).foregroundStyle(.secondary)
                    Button("Keep a copy and start fresh") {
                        deletes.recover(artefact)
                        imports.reload()
                    }
                }
            }
        }
    }
}

@MainActor
final class DataDeleteModel: ObservableObject {
    @Published private(set) var notice: String?
    @Published private(set) var noticeIsFailure = false
    @Published private(set) var blocked: [StoreArtefact: String] = [:]
    private let wipe = DataWipe()
    var blockedList: [StoreArtefact] { blocked.keys.sorted { $0.rawValue < $1.rawValue } }
    init() { blocked = wipe.blockedArtefacts() }

    func perform(_ action: DataDeleteAction) {
        let result = wipe.perform(action)
        notice = result.message
        noticeIsFailure = !result.isComplete
        blocked = wipe.blockedArtefacts()
    }

    func recover(_ artefact: StoreArtefact) {
        do {
            notice = try wipe.recover(artefact).map { "Kept a copy as \($0.lastPathComponent)." } ?? "Nothing was there to move aside."
            noticeIsFailure = false
        } catch {
            notice = error.localizedDescription
            noticeIsFailure = true
        }
        blocked = wipe.blockedArtefacts()
    }
}
