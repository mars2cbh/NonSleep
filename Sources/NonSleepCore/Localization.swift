import Foundation

public enum AppLanguage: String, CaseIterable {
    case system, english = "en", korean = "ko"

    public func resolvedCode(preferredLanguages: [String]) -> String {
        if self != .system { return rawValue }
        return Bundle.preferredLocalizations(from: ["en", "ko"], forPreferences: preferredLanguages).first ?? "en"
    }
}

public enum L10n {
    public static let preferenceKey = "appLanguage"
    private final class ResourceAnchor: NSObject {}

    // Also works for the separately installed command-line helper, which has no
    // resource bundle. In that case the English source string is the fallback.
    private static let resources: Bundle? = {
        let name = "NonSleep_NonSleepCore.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(name),
            Bundle.main.bundleURL.appendingPathComponent(name),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name),
            Bundle(for: ResourceAnchor.self).bundleURL.deletingLastPathComponent().appendingPathComponent(name)
        ]
        return candidates.compactMap { $0.flatMap(Bundle.init(url:)) }.first
    }()

    public static var languageCode: String {
        let choice = AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
        let preferred = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
        return choice.resolvedCode(preferredLanguages: preferred)
    }

    public static func string(_ key: String, language: String) -> String {
        guard let path = resources?.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let code = languageCode
        let format = string(key, language: code)
        return arguments.isEmpty ? format : String(format: format, locale: Locale(identifier: code), arguments: arguments)
    }
}
