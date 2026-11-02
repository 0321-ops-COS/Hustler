import Foundation
import SwiftUI
import HustlerCore

/// Home screen state. The only derived value is the decline-float card, and it
/// comes from the same stored master log the rest of the app uses.
@MainActor
final class HomeViewModel: ObservableObject {

    /// Settings persistence is not ported yet, so the card uses the web app's
    /// defaults (`DEF.accept` 89, `DEF.target` 85). The newest logged rate still
    /// wins inside `DeclineFloat`.
    static let defaultSettingsRate: Double = 89
    static let defaultTarget: Double = 85

    @Published private(set) var float: HomeFloat.Card

    init(store: LocalStore = LocalStore()) {
        float = Self.card(from: LocalLibrary(store: store).log)
    }

    /// A pure function of the stored text, so a save elsewhere refreshes it the
    /// same way.
    static func card(from document: MasterLogDocument) -> HomeFloat.Card {
        HomeFloat.card(
            rows: MasterLogParser.parse(document.text),
            settingsRate: defaultSettingsRate,
            target: defaultTarget
        )
    }
}
