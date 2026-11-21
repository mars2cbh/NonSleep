import SwiftUI
import AppKit
import Combine

@main
@MainActor
enum NonSleepApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var statusObservation: AnyCancellable?
    private var settingsObservation: AnyCancellable?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let appMenu = NSMenu(title: "NonSleep")
        let settingsItem = NSMenuItem(title: "설정…", action: #selector(openGeneralSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        let updateItem = NSMenuItem(title: "업데이트 확인…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(updateItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "NonSleep 종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        let menuBar = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        menuBar.addItem(appMenuItem)
        NSApp.mainMenu = menuBar

        let controller = NSHostingController(rootView: Dashboard(model: model))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true

        let item = NSStatusBar.system.statusItem(withLength: 30)
        item.autosaveName = "NonSleepStatusItem"
        item.isVisible = true
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        statusObservation = model.$awake.combineLatest(model.$lid, model.$focusRequest)
            .sink { [weak self] awake, lid, focus in
                self?.updateStatusIcon(appearance: StatusAppearance(awake: awake, lid: lid, focus: focus == true))
            }
        settingsObservation = model.$showingSettings.dropFirst().sink { [weak self] show in
            if show { self?.showSettingsWindow() }
            else { self?.settingsWindow?.orderOut(nil) }
        }
        Task { await model.refresh() }
        model.updates.startAutomaticChecks()
    }

    private func showSettingsWindow() {
        // A sheet attached to a transient popover can remain modal after the
        // popover disappears. Keep settings in its own nonmodal window instead.
        popover.performClose(nil)
        if settingsWindow == nil {
            let view = SettingsView(model: model) { [weak self] in
                self?.model.showingSettings = false
            }
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "NonSleep 설정"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        Task { await model.settings.refresh() }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow, model.showingSettings {
            model.showingSettings = false
        }
    }

    private func updateStatusIcon(appearance: StatusAppearance) {
        guard let button = statusItem?.button else { return }
        button.image = appearance.makeStatusImage()
        button.imagePosition = .imageOnly
        button.toolTip = "NonSleep · \(appearance.activeCount)개 기능 사용 중\n\(appearance.featureDescription)\n클릭: 제어판 · 우클릭: 빠른 제어"
        button.setAccessibilityLabel("NonSleep, \(appearance.featureDescription)")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
        Task { await model.refresh() }
    }

    private func showQuickMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        popover.performClose(nil)
        let menu = NSMenu(title: "NonSleep")
        menu.autoenablesItems = false
        menu.delegate = self
        let heading = NSMenuItem(title: "NonSleep", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        addItem(to: menu, title: "잠자기 방지", action: #selector(toggleAwake),
                state: model.awake ? .on : .off, enabled: model.busy == nil)
        addItem(to: menu, title: "덮어도 깨어 있기", action: #selector(toggleLid),
                state: model.lidKnown ? (model.lid ? .on : .off) : .mixed,
                enabled: model.busy == nil && model.lidKnown)
        addItem(to: menu, title: model.focusConfigured ? "방해 금지" : "방해 금지 연결…",
                action: #selector(toggleFocus),
                state: model.focusRequest.map { $0 ? .on : .off } ?? .mixed, enabled: model.busy == nil)
        if model.focusConfigured {
            addItem(to: menu, title: "방해 금지 끄기 실행", action: #selector(turnFocusOff), enabled: model.busy == nil)
        }
        menu.addItem(.separator())
        addItem(to: menu, title: "제어판 열기", action: #selector(openDashboard))
        addItem(to: menu, title: "설정…", action: #selector(openGeneralSettings))
        addItem(to: menu, title: "업데이트 확인…", action: #selector(checkForUpdates))
        menu.addItem(.separator())
        addItem(to: menu, title: "NonSleep 종료", action: #selector(quit), enabled: model.busy == nil)
        statusItem.menu = menu
        button.performClick(nil)
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector,
                         state: NSControl.StateValue = .off, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = state
        item.isEnabled = enabled
        menu.addItem(item)
    }

    func menuDidClose(_ menu: NSMenu) { statusItem?.menu = nil }

    @objc private func toggleAwake() { model.setAwake(!model.awake) }
    @objc private func toggleLid() { Task { await model.setLid(!model.lid) } }
    @objc private func toggleFocus() {
        guard model.focusConfigured else { openFocusSetup(); return }
        Task { await model.setFocus(model.focusRequest != true) }
    }
    @objc private func turnFocusOff() { Task { await model.setFocus(false) } }
    @objc private func openDashboard() { showPopover() }
    @objc private func openFocusSetup() {
        model.openSettings(.focus)
    }
    @objc private func openGeneralSettings() {
        model.openSettings()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() {
        model.openSettings(.updates)
        Task { await model.updates.checkNow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settingsWindow?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow?.makeKeyAndOrderFront(nil)
        } else { showPopover() }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let canQuit = await model.prepareToQuit()
            if !canQuit { showPopover() }
            sender.reply(toApplicationShouldTerminate: canQuit)
        }
        return .terminateLater
    }
}
