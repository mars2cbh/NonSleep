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
    @Published private(set) var shortcuts: [FocusShortcut] = []
    @Published private(set) var loadingShortcuts = false
    @Published private(set) var focusError: String?
    @Published private(set) var focusFeedback: String?
    @Published var errorMessage: String?
    @Published var showingSettings = false
    @Published var settingsTab: SettingsTab = .general
    @Published var shortcutOn: String { didSet { defaults.set(shortcutOn, forKey: "shortcutOn"); resetFocusFeedback() } }
    @Published var shortcutOff: String { didSet { defaults.set(shortcutOff, forKey: "shortcutOff"); resetFocusFeedback() } }
    @Published private(set) var recovery: LidRecovery?

    private let defaults: UserDefaults
    private let focusService: FocusShortcutRunning
    let settings = AppSettings()
    let updates = AppUpdates()
    let hotkeys = HotKeySettings()
    private let power = AwakeService()
    private var quitting = false
    var focusConfigured: Bool { !shortcutOn.isEmpty && !shortcutOff.isEmpty && shortcutOn != shortcutOff }
    var activeCount: Int { (awake ? 1 : 0) + (lid ? 1 : 0) + (focusRequest == true ? 1 : 0) }
    var statusAppearance: StatusAppearance { StatusAppearance(awake: awake, lid: lid, focus: focusRequest == true) }

    init(defaults: UserDefaults = .standard, focusService: FocusShortcutRunning = FocusService()) {
        self.defaults = defaults
        self.focusService = focusService
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
        guard !loadingShortcuts, busy != "focus" else { return }
        loadingShortcuts = true
        defer { loadingShortcuts = false }
        do {
            shortcuts = try await focusService.list()
            migrateShortcutSelections()
            focusError = nil
        } catch { focusError = L10n.tr("Could not load shortcuts. %@", error.localizedDescription) }
    }

    func setFocus(_ enabled: Bool) async {
        guard busy == nil, !loadingShortcuts else { return }
        guard !(enabled ? shortcutOn : shortcutOff).isEmpty else { openSettings(.focus); return }
        busy = "focus"
        focusError = nil
        focusFeedback = nil
        defer { busy = nil }
        do {
            // Recheck the catalog so a deleted or renamed shortcut cannot run
            // by a stale name. Stable identifiers also disambiguate names.
            shortcuts = try await focusService.list()
            let shortcut = try FocusService.resolve(enabled ? shortcutOn : shortcutOff, in: shortcuts)
            let other = try? FocusService.resolve(enabled ? shortcutOff : shortcutOn, in: shortcuts)
            guard shortcut.id != other?.id else {
                throw AppError.message(L10n.tr("Choose different shortcuts for On and Off."))
            }
            migrateShortcutSelections()
            try await focusService.run(identifier: shortcut.id)
            focusRequest = enabled
            focusFeedback = enabled
                ? L10n.tr("On shortcut finished. Check Do Not Disturb in Control Center; completion alone does not confirm Focus changed.")
                : L10n.tr("Off shortcut finished. Check Do Not Disturb in Control Center; completion alone does not confirm Focus changed.")
        } catch {
            // A shortcut may partially run before failing. Do not display a stale success state.
            focusRequest = nil
            let message = L10n.tr("Could not run the Do Not Disturb shortcut. %@ Open it in Shortcuts and run it once to check its actions and any permission prompts.", error.localizedDescription)
            focusError = message
            if !showingSettings { errorMessage = message }
        }
    }

    private func resetFocusFeedback() {
        focusRequest = nil
        focusFeedback = nil
        focusError = nil
    }

    private func migrateShortcutSelections() {
        if let shortcut = try? FocusService.resolve(shortcutOn, in: shortcuts), shortcutOn != shortcut.id {
            shortcutOn = shortcut.id
        }
        if let shortcut = try? FocusService.resolve(shortcutOff, in: shortcuts), shortcutOff != shortcut.id {
            shortcutOff = shortcut.id
        }
    }

    func editFocusShortcut(_ selection: String) {
        Task {
            do {
                let shortcut = try FocusService.resolve(selection, in: shortcuts)
                guard shortcuts.filter({ $0.name == shortcut.name }).count == 1 else {
                    openShortcuts()
                    return
                }
                _ = try await Commands.checked("/usr/bin/shortcuts", ["view", shortcut.name])
            } catch { focusError = error.localizedDescription }
        }
    }

    /// Called by AppDelegate even for Command-Q / external normal termination requests.
    func prepareToQuit() async -> Bool {
        guard !quitting else { return false }
        guard busy == nil, !settings.busy else {
            errorMessage = L10n.tr("Wait for the current action to finish before quitting.")
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
