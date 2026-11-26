import XCTest
@testable import NonSleep

private final class FakeFocusService: FocusShortcutRunning {
    var shortcuts: [FocusShortcut] = []
    var error: Error?
    var listError: Error?
    var runs: [String] = []
    func list() async throws -> [FocusShortcut] {
        if let listError { throw listError }
        return shortcuts
    }
    func run(identifier: String) async throws {
        runs.append(identifier)
        if let error { throw error }
    }
}

final class FocusServiceTests: XCTestCase {
    private let on = FocusShortcut(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "방해 금지 (켜기)")
    private let off = FocusShortcut(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", name: "Focus Off")

    func testCatalogPreservesUnicodeParenthesesAndDuplicateNamesWithDistinctIDs() throws {
        let output = "\(on.name) (\(on.id))\n\(on.name) (\(off.id))\n"
        let shortcuts = try FocusService.parse(output)
        XCTAssertEqual(Set(shortcuts.map(\.id)), Set([on.id, off.id]))
        XCTAssertTrue(shortcuts.allSatisfy { $0.name == on.name })
        XCTAssertThrowsError(try FocusService.resolve(on.name, in: shortcuts))
        XCTAssertEqual(try FocusService.resolve(on.id.lowercased(), in: shortcuts).id, on.id)
        XCTAssertThrowsError(try FocusService.parse("Unexpected CLI output"))
        XCTAssertEqual(try FocusService.parse(""), [])
    }

    @MainActor
    func testLegacyNamesMigrateAndRenamedShortcutRunsByIdentifier() async throws {
        let (model, service, defaults) = makeModel()
        model.shortcutOn = on.name
        model.shortcutOff = off.name
        await model.loadShortcuts()
        XCTAssertEqual(model.shortcutOn, on.id)
        XCTAssertEqual(defaults.string(forKey: "shortcutOff"), off.id)
        service.shortcuts[0] = FocusShortcut(id: on.id, name: "Renamed on another device")
        await model.setFocus(true)
        XCTAssertEqual(service.runs, [on.id])
        XCTAssertEqual(model.focusRequest, true)
        await model.setFocus(false)
        XCTAssertEqual(service.runs, [on.id, off.id])
        XCTAssertEqual(model.focusRequest, false)
        XCTAssertNotNil(model.focusFeedback)
    }

    @MainActor
    func testDeletedShortcutDoesNotRunAnotherShortcutWithItsOldName() async {
        let (model, service, _) = makeModel()
        model.shortcutOn = on.id
        model.shortcutOff = off.id
        service.shortcuts = [off, FocusShortcut(id: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC", name: on.name)]
        model.showingSettings = true
        await model.setFocus(true)
        XCTAssertTrue(service.runs.isEmpty)
        XCTAssertNil(model.focusRequest)
        XCTAssertNotNil(model.focusError)
        XCTAssertNil(model.errorMessage, "Settings must display the failure inline, not on the hidden popover")
    }

    @MainActor
    func testOffStillRunsWhenOnShortcutWasDeleted() async {
        let (model, service, _) = makeModel()
        model.shortcutOn = on.id
        model.shortcutOff = off.id
        service.shortcuts = [off]
        await model.setFocus(false)
        XCTAssertEqual(service.runs, [off.id])
        XCTAssertEqual(model.focusRequest, false)
    }

    @MainActor
    func testExecutionFailureClearsPreviousSuccessAndDisplaysDetailsInSettings() async {
        let (model, service, _) = makeModel()
        model.shortcutOn = on.id
        model.shortcutOff = off.id
        model.showingSettings = true
        await model.setFocus(true)
        service.error = AppError.message("Permission denied by Shortcuts")
        await model.setFocus(false)
        XCTAssertNil(model.focusRequest)
        XCTAssertNil(model.focusFeedback)
        XCTAssertTrue(model.focusError?.contains("Permission denied by Shortcuts") == true)
        XCTAssertNil(model.busy)
    }

    @MainActor
    func testListFailureIsVisibleAndSelectionChangeClearsStaleSuccess() async {
        let (model, service, _) = makeModel()
        model.shortcutOn = on.id
        model.shortcutOff = off.id
        await model.setFocus(true)
        model.shortcutOn = "another shortcut"
        XCTAssertNil(model.focusRequest)
        XCTAssertNil(model.focusFeedback)
        service.listError = AppError.message("Shortcuts database unavailable")
        await model.loadShortcuts()
        XCTAssertTrue(model.focusError?.contains("Shortcuts database unavailable") == true)
        XCTAssertFalse(model.loadingShortcuts)
    }

    @MainActor
    private func makeModel() -> (AppModel, FakeFocusService, UserDefaults) {
        let suite = "NonSleep-focus-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let service = FakeFocusService()
        service.shortcuts = [on, off]
        return (AppModel(defaults: defaults, focusService: service), service, defaults)
    }
}
