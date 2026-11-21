import XCTest
@testable import NonSleepCore

final class LocalizationTests: XCTestCase {
    func testAutomaticLanguageMatchesSupportedPreferencesAndFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["ko-KR", "en-US"]), "ko")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["en-GB", "ko-KR"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["fr-FR", "ko-KR"]), "ko")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(AppLanguage.english.resolvedCode(preferredLanguages: ["ko"]), "en")
        XCTAssertEqual(AppLanguage.korean.resolvedCode(preferredLanguages: ["en"]), "ko")
    }

    func testResourceBundlesAreLoadedAndFormattingRetainsRuntimeValues() {
        XCTAssertEqual(L10n.string("Keep Awake", language: "ko"), "잠자기 방지")
        XCTAssertEqual(L10n.string("Keep Awake", language: "en"), "Keep Awake")
        XCTAssertEqual(L10n.string("Settings…", language: "ko"), "설정…")
        let key = "Could not connect to GitHub. (HTTP %d)"
        XCTAssertEqual(String(format: L10n.string(key, language: "ko"), 429), "GitHub에 연결하지 못했습니다. (HTTP 429)")
        XCTAssertEqual(L10n.string("A diagnostic without a catalog entry", language: "ko"), "A diagnostic without a catalog entry")
    }
}
