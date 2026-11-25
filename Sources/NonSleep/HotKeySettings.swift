import AppKit
import Carbon
import Combine
import NonSleepCore

enum HotKeyAction: Int, CaseIterable, Codable {
    case awake, lid, focus
    var title: String {
        switch self {
        case .awake: return L10n.tr("Keep Awake")
        case .lid: return L10n.tr("Stay Awake with Lid Closed")
        case .focus: return L10n.tr("Do Not Disturb")
        }
    }
    var defaultBinding: HotKeyBinding {
        HotKeyBinding(keyCode: [18, 19, 20][rawValue], modifiers: [.control, .option, .command])
    }
}

struct HotKeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt32
    static let control = Self(rawValue: 1)
    static let option = Self(rawValue: 2)
    static let shift = Self(rawValue: 4)
    static let command = Self(rawValue: 8)
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }
    init(rawValue: UInt32) { self.rawValue = rawValue }
    init(eventFlags: NSEvent.ModifierFlags) {
        var flags: Self = []
        if eventFlags.contains(.control) { flags.insert(.control) }
        if eventFlags.contains(.option) { flags.insert(.option) }
        if eventFlags.contains(.shift) { flags.insert(.shift) }
        if eventFlags.contains(.command) { flags.insert(.command) }
        self = flags
    }
    var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

struct HotKeyBinding: Codable, Hashable {
    let keyCode: UInt32
    let modifiers: HotKeyModifiers
    var isValid: Bool {
        keyCode <= 127 && modifiers.rawValue & ~UInt32(15) == 0
            && (!modifiers.intersection([.control, .option]).isEmpty)
    }
    var display: String { modifiers.symbols + Self.keyName(keyCode) }
    static func keyName(_ code: UInt32) -> String {
        let special: [UInt32: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤",
            115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        if let name = special[code] { return name }
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = unsafeBitCast(pointer, to: CFData.self)
            let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
            var dead: UInt32 = 0, count: Int = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let result = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, 8, &count, &characters)
            if result == noErr && count > 0 {
                return String(utf16CodeUnits: characters, count: count).uppercased()
            }
        }
        return "#\(code)"
    }
}

@MainActor
protocol HotKeyRegistering: AnyObject {
    func register(_ binding: HotKeyBinding, id: UInt32, onPress: @escaping () -> Void) throws
    func unregisterAll()
}

struct HotKeyRegistrationError: Error { let status: OSStatus }

@MainActor
final class CarbonHotKeyRegistry: HotKeyRegistering {
    private var eventHandler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private var bindings: [UInt32: HotKeyBinding] = [:]
    private var localMonitor: Any?
    private var callbacks: [UInt32: () -> Void] = [:]
    private var pressedIDs: Set<UInt32> = []
    private static let signature: OSType = 0x4E534C50 // NSLP

    func register(_ binding: HotKeyBinding, id: UInt32, onPress: @escaping () -> Void) throws {
        if eventHandler == nil {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                         EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var hotKey = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
                guard status == noErr, hotKey.signature == 0x4E534C50 else { return OSStatus(eventNotHandledErr) }
                let registry = Unmanaged<CarbonHotKeyRegistry>.fromOpaque(context).takeUnretainedValue()
                let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                MainActor.assumeIsolated { registry.receive(hotKey.id, down: down) }
                return noErr
            }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            guard status == noErr else { throw HotKeyRegistrationError(status: status) }
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers.carbonFlags,
            EventHotKeyID(signature: Self.signature, id: id), GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr, let reference else { throw HotKeyRegistrationError(status: status) }
        references.append(reference)
        callbacks[id] = onPress
        bindings[id] = binding
        if localMonitor == nil {
            // AppKit may deliver foreground events directly instead of through
            // Carbon (for example while a control has keyboard focus).
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return event }
                    let modifiers = HotKeyModifiers(eventFlags: event.modifierFlags)
                    guard let match = self.bindings.first(where: {
                        $0.value.keyCode == UInt32(event.keyCode)
                            && (event.type == .keyUp ? self.pressedIDs.contains($0.key) : $0.value.modifiers == modifiers)
                    }) else { return event }
                    self.receive(match.key, down: event.type == .keyDown)
                    return nil
                }
            }
        }
    }

    private func receive(_ id: UInt32, down: Bool) {
        if down {
            guard pressedIDs.insert(id).inserted else { return }
            callbacks[id]?()
        } else { pressedIDs.remove(id) }
    }

    func unregisterAll() {
        pressedIDs.removeAll()
        bindings.removeAll()
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        callbacks.removeAll()
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        references.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

@MainActor
final class HotKeySettings: ObservableObject {
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "hotkeysEnabled"); apply() } }
    @Published private(set) var bindings: [HotKeyAction: HotKeyBinding]
    @Published private(set) var errors: [HotKeyAction: OSStatus] = [:]
    @Published private(set) var validationMessage: String?
    private let defaults: UserDefaults
    private let registry: any HotKeyRegistering
    private var handler: ((HotKeyAction) -> Void)?
    private var recording = false

    init(defaults: UserDefaults = .standard, registry: (any HotKeyRegistering)? = nil) {
        self.defaults = defaults
        self.registry = registry ?? CarbonHotKeyRegistry()
        enabled = defaults.object(forKey: "hotkeysEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "hotkeyBindings"),
           let saved = try? JSONDecoder().decode([HotKeyAction: HotKeyBinding].self, from: data),
           saved.values.allSatisfy(\.isValid) { bindings = saved }
        else { bindings = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultBinding) }) }
    }

    func start(handler: @escaping (HotKeyAction) -> Void) { self.handler = handler; apply() }
    func stop() { registry.unregisterAll(); handler = nil }
    func setRecording(_ value: Bool) { guard recording != value else { return }; recording = value; apply() }

    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        validationMessage = nil
        if let binding {
            guard binding.isValid else {
                validationMessage = L10n.tr("Include Control (⌃) or Option (⌥) in your shortcut.")
                return
            }
            guard !bindings.contains(where: { $0.key != action && $0.value == binding }) else {
                validationMessage = L10n.tr("That shortcut is already assigned to another feature.")
                return
            }
        }
        bindings[action] = binding
        persist()
        apply()
    }

    func restoreDefaults() {
        bindings = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultBinding) })
        validationMessage = nil
        persist()
        apply()
    }

    private func persist() { defaults.set(try? JSONEncoder().encode(bindings), forKey: "hotkeyBindings") }
    private func apply() {
        registry.unregisterAll()
        errors = [:]
        guard handler != nil, enabled, !recording else { return }
        for action in HotKeyAction.allCases {
            guard let binding = bindings[action] else { continue }
            do {
                try registry.register(binding, id: UInt32(action.rawValue + 1)) { [weak self] in
                    guard let self, self.enabled, !self.recording else { return }
                    self.handler?(action)
                }
            } catch { errors[action] = (error as? HotKeyRegistrationError)?.status ?? -1 }
        }
    }
}
