import Foundation
import Combine
import HustlerCore

/// Check-tab state. Field parsing, rate precedence and the verdict are
/// `CheckModel`'s; this class only loads the log and settings, holds the boxes
/// and saves the rate when the helper is used.
@MainActor
final class CheckViewModel: ObservableObject {
    @Published private(set) var model: CheckModel
    @Published private(set) var outcome: CheckModel.Outcome?
    @Published private(set) var message: String?

    private let settingsStore: SettingsStore

    init(store: LocalStore = LocalStore()) {
        let settingsStore = SettingsStore(store: store)
        self.settingsStore = settingsStore
        let rows = MasterLog.orderedForAnalysis(
            MasterLogParser.parse(LocalLibrary(store: store).log.text)
        )
        model = CheckModel(
            settings: settingsStore.settings.verdictSettings(),
            settingsRate: settingsStore.settings.accept,
            rows: rows
        )
    }

    var logRateHint: String? { model.logRateHint }

    func text(for field: CheckModel.Field) -> String { model.text(for: field) }

    func setText(_ text: String, for field: CheckModel.Field) {
        model.setText(text, for: field)
    }

    func getVerdict() {
        message = nil
        outcome = model.outcome()
    }

    /// `useLR()`: fills the field and stores the rate, as the web app does.
    func useLogRate() {
        guard model.logRateHint != nil else { return }
        model.useLogRate()
        var settings = settingsStore.settings
        settings.accept = model.resolvedRate.rate
        do {
            try settingsStore.save(settings)
            message = "Acceptance rate set to \(JsNumber.description(model.resolvedRate.rate))."
        } catch {
            message = error.localizedDescription
        }
    }
}
