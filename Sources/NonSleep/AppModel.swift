import AppKit
import Combine
import NonSleepCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var awake = false
    @Published private(set) var lid = false
    @Published private(set) var lidKnown = false
    @Published private(set) var focusRequest: Bool? = nil
    @Published private(set) var busy: String?
    @Published private(set) var shortcuts: [String] = []
    @Published private(set) var loadingShortcuts = false
    @Published var errorMessage: String?
    @Published var showingSettings = false
    @Published var settingsTab: SettingsTab = .general
    @Published var shortcutOn: String { didSet { defaults.set(shortcutOn, forKey: "shortcutOn") } }
    @Published var shortcutOff: String { didSet { defaults.set(shortcutOff, forKey: "shortcutOff") } }
    @Published private(set) var recovery: LidRecovery?

    private let defaults: UserDefaults
    let settings = AppSettings()
    private let power = AwakeService()
    private var quitting = false
    var focusConfigured: Bool { !shortcutOn.isEmpty && !shortcutOff.isEmpty && shortcutOn != shortcutOff }
    var activeCount: Int { (awake ? 1 : 0) + (lid ? 1 : 0) + (focusRequest == true ? 1 : 0) }
    var statusAppearance: StatusAppearance { StatusAppearance(awake: awake, lid: lid, focus: focusRequest == true) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcutOn = defaults.string(forKey: "shortcutOn") ?? ""
        shortcutOff = defaults.string(forKey: "shortcutOff") ?? ""
        if let data = defaults.data(forKey: "lidRecovery") {
            recovery = try? JSONDecoder().decode(LidRecovery.self, from: data)
        }
    }

    func refresh() async {
        guard busy == nil else { return }
        do {
            lid = try await LidService.read()
            lidKnown = true
            if let recovery, lid == recovery.originalDisabled { clearRecovery() }
        } catch {
            lidKnown = false
            errorMessage = error.localizedDescription
        }
        await settings.refresh()
    }

    func setAwake(_ enabled: Bool) {
        do {
            if enabled { try power.enable() } else { power.disable() }
            awake = enabled
        } catch { errorMessage = error.localizedDescription }
    }

    func setLid(_ enabled: Bool) async {
        guard busy == nil, !settings.busy, lidKnown else { return }
        busy = "lid"
        defer { busy = nil }
        do {
            // Re-read immediately before changing, so an external setting is not mistaken for ours.
            let current = try await LidService.read()
            lid = current
            guard current != enabled else {
                if let recovery, current == recovery.originalDisabled { clearRecovery() }
                return
            }
            if enabled, recovery == nil {
                let record = LidRecovery(originalDisabled: current)
                defaults.set(try JSONEncoder().encode(record), forKey: "lidRecovery")
                // Flush before the privileged operation: it may outlive this process.
                defaults.synchronize()
                recovery = record
            }
            try await LidService.set(enabled)
            lid = enabled
            if let recovery, enabled == recovery.originalDisabled { clearRecovery() }
        } catch {
            if let current = try? await LidService.read() {
                lid = current
                if let recovery, current == recovery.originalDisabled { clearRecovery() }
            } else { lidKnown = false }
            errorMessage = error.localizedDescription
        }
    }

    func restoreLid() async {
        guard let recovery else { return }
        await setLid(recovery.originalDisabled)
    }

    private func clearRecovery() {
        defaults.removeObject(forKey: "lidRecovery")
        defaults.synchronize()
        recovery = nil
    }

    func loadShortcuts() async {
        guard !loadingShortcuts else { return }
        loadingShortcuts = true
        defer { loadingShortcuts = false }
        do {
            let output = try await Commands.checked("/usr/bin/shortcuts", ["list"])
            shortcuts = output.components(separatedBy: .newlines).filter { !$0.isEmpty }.sorted()
        } catch { errorMessage = "단축어 목록을 가져오지 못했습니다. \(error.localizedDescription)" }
    }

    func setFocus(_ enabled: Bool) async {
        guard busy == nil else { return }
        guard focusConfigured else { openSettings(.focus); return }
        busy = "focus"
        defer { busy = nil }
        do {
            // Pass names as arguments, never through a shell.
            _ = try await Commands.checked("/usr/bin/shortcuts", ["run", enabled ? shortcutOn : shortcutOff], timeout: 120)
            focusRequest = enabled
        } catch {
            // A shortcut may partially run before failing. Do not display a stale success state.
            focusRequest = nil
            errorMessage = "방해 금지 단축어 실행을 확인하지 못했습니다. \(error.localizedDescription)"
        }
    }

    /// Called by AppDelegate even for Command-Q / external normal termination requests.
    func prepareToQuit() async -> Bool {
        guard !quitting else { return false }
        guard busy == nil, !settings.busy else {
            errorMessage = "진행 중인 작업이 끝나면 종료해 주세요."
            return false
        }
        quitting = true
        defer { quitting = false }
        if recovery != nil {
            if !lidKnown { await refresh() }
            guard lidKnown else { return false }
            await restoreLid()
            guard recovery == nil else { return false }
        }
        power.disable()
        awake = false
        return true
    }

    func openShortcuts() { NSWorkspace.shared.open(URL(string: "shortcuts://")!) }
    func openSettings(_ tab: SettingsTab = .general) {
        settingsTab = tab
        showingSettings = true
    }
    func openFocusSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")!)
    }
}
