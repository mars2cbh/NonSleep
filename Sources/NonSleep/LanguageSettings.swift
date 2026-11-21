import Combine
import Foundation
import NonSleepCore

@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    @Published var selection: AppLanguage {
        didSet {
            defaults.set(selection.rawValue, forKey: L10n.preferenceKey)
            // Foundation/Sparkle read this standard per-app preference at launch.
            if selection == .system { defaults.removeObject(forKey: "AppleLanguages") }
            else { defaults.set([selection.rawValue], forKey: "AppleLanguages") }
        }
    }
    private let defaults: UserDefaults
    var locale: Locale { Locale(identifier: L10n.languageCode) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = AppLanguage(rawValue: defaults.string(forKey: L10n.preferenceKey) ?? "") ?? .system
    }
}
