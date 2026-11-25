import XCTest
import Carbon
@testable import NonSleep

@MainActor
final class HotKeySettingsTests: XCTestCase {
    private func makeSettings() throws -> (HotKeySettings, MockHotKeyRegistry, UserDefaults) {
        let suite = "dev.nonsleep.tests.hotkeys.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let registry = MockHotKeyRegistry()
        return (HotKeySettings(defaults: defaults, registry: registry), registry, defaults)
    }

    func testNativeCarbonEventBridgeAndRepeatSuppression() throws {
        let registry = CarbonHotKeyRegistry()
        defer { registry.unregisterAll() }
        var count = 0
        do {
            try registry.register(HotKeyBinding(keyCode: 80, modifiers: [.control, .option, .command]), id: 72) { count += 1 }
        } catch let error as HotKeyRegistrationError {
            throw XCTSkip("Native hotkey unavailable in this session: \(error.status)")
        }
        func send(_ kind: Int) throws {
            var event: EventRef?
            XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kind), GetCurrentEventTime(), 0, &event), noErr)
            let value = try XCTUnwrap(event)
            defer { ReleaseEvent(value) }
            var identifier = EventHotKeyID(signature: 0x4E534C50, id: 72)
            XCTAssertEqual(SetEventParameter(value, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                            MemoryLayout<EventHotKeyID>.size, &identifier), noErr)
            XCTAssertEqual(SendEventToEventTarget(value, GetEventDispatcherTarget()), noErr)
        }
        try send(kEventHotKeyPressed)
        try send(kEventHotKeyPressed)
        XCTAssertEqual(count, 1, "Holding a hotkey must not repeatedly toggle the feature")
        try send(kEventHotKeyReleased)
        try send(kEventHotKeyPressed)
        XCTAssertEqual(count, 2)
    }

    func testDefaultBindingsAndModifierValidation() throws {
        let (settings, registry, _) = try makeSettings()
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(Set(settings.bindings.values).count, 3)
        XCTAssertTrue(settings.bindings.values.allSatisfy(\.isValid))
        XCTAssertEqual(HotKeyAction.awake.defaultBinding.keyCode, 18)
        XCTAssertEqual(HotKeyAction.awake.defaultBinding.modifiers.symbols, "⌃⌥⌘")
        XCTAssertFalse(HotKeyBinding(keyCode: 0, modifiers: [.command]).isValid)
        XCTAssertFalse(HotKeyBinding(keyCode: 128, modifiers: [.control]).isValid)
        XCTAssertTrue(registry.handlers.isEmpty, "Construction must not register system hotkeys")
    }

    func testDispatchDisableRecordingAndStopDoNotFireStaleCallbacks() throws {
        let (settings, registry, _) = try makeSettings()
        var actions: [HotKeyAction] = []
        settings.start { actions.append($0) }
        XCTAssertEqual(registry.handlers.count, 3)
        registry.handlers[1]?()
        XCTAssertEqual(actions, [.awake])
        let stale = registry.handlers[1]
        settings.setRecording(true)
        XCTAssertTrue(registry.handlers.isEmpty)
        stale?()
        XCTAssertEqual(actions.count, 1)
        settings.setRecording(false)
        registry.handlers[3]?()
        XCTAssertEqual(actions, [.awake, .focus])
        settings.enabled = false
        XCTAssertTrue(registry.handlers.isEmpty)
        stale?()
        XCTAssertEqual(actions.count, 2)
        settings.enabled = true
        XCTAssertEqual(registry.handlers.count, 3)
        settings.stop()
        stale?()
        XCTAssertTrue(registry.handlers.isEmpty)
        XCTAssertEqual(actions.count, 2)
    }

    func testCustomizationClearingPersistenceAndDuplicates() throws {
        let (settings, _, defaults) = try makeSettings()
        let customized = HotKeyBinding(keyCode: 0, modifiers: [.control, .option])
        settings.setBinding(customized, for: .awake)
        XCTAssertEqual(HotKeySettings(defaults: defaults).bindings[.awake], customized)
        settings.setBinding(customized, for: .lid)
        XCTAssertEqual(settings.bindings[.lid], HotKeyAction.lid.defaultBinding)
        XCTAssertNotNil(settings.validationMessage)
        settings.setBinding(HotKeyBinding(keyCode: 0, modifiers: []), for: .awake)
        XCTAssertEqual(settings.bindings[.awake], customized)
        settings.setBinding(nil, for: .awake)
        XCTAssertNil(HotKeySettings(defaults: defaults).bindings[.awake])
        settings.restoreDefaults()
        XCTAssertEqual(settings.bindings[.awake], HotKeyAction.awake.defaultBinding)
    }

    func testConflictsAreReportedWithoutDisablingOtherFeatures() throws {
        let (settings, registry, _) = try makeSettings()
        registry.conflictingID = 2
        settings.start { _ in }
        XCTAssertNotNil(settings.errors[.lid])
        XCTAssertNil(registry.handlers[2])
        XCTAssertNotNil(registry.handlers[1])
        XCTAssertNotNil(registry.handlers[3])
        registry.conflictingID = nil
        settings.setRecording(true)
        settings.setRecording(false)
        XCTAssertTrue(settings.errors.isEmpty)
        XCTAssertEqual(registry.handlers.count, 3)
    }
}

@MainActor
private final class MockHotKeyRegistry: HotKeyRegistering {
    var handlers: [UInt32: () -> Void] = [:]
    var conflictingID: UInt32?
    func register(_ binding: HotKeyBinding, id: UInt32, onPress: @escaping () -> Void) throws {
        if id == conflictingID { throw HotKeyRegistrationError(status: -9878) }
        handlers[id] = onPress
    }
    func unregisterAll() { handlers.removeAll() }
}
