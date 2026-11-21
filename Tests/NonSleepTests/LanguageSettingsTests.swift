import XCTest
import NonSleepCore
@testable import NonSleep

@MainActor
final class LanguageSettingsTests: XCTestCase {
    func testPreferencePersistsAndSystemChoiceRemovesFrameworkOverride() throws {
        let suite = "dev.nonsleep.tests.language.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LanguageSettings(defaults: defaults)
        XCTAssertEqual(settings.selection, .system)
        settings.selection = .english
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
        XCTAssertEqual(LanguageSettings(defaults: defaults).selection, .english)
        settings.selection = .korean
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["ko"])
        XCTAssertEqual(LanguageSettings(defaults: defaults).selection, .korean)
        settings.selection = .system
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
        XCTAssertEqual(LanguageSettings(defaults: defaults).selection, .system)
    }
}
