import SwiftUI
import NonSleepCore

struct HotKeySettingsView: View {
    @ObservedObject var hotkeys: HotKeySettings
    @ObservedObject private var language = LanguageSettings.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.fill").font(.system(size: 30)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Global Hotkeys")).font(.system(size: 21, weight: .semibold))
                    Text(L10n.tr("Control NonSleep while using another app."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Toggle(L10n.tr("Enable global hotkeys"), isOn: $hotkeys.enabled)
                .toggleStyle(.switch).font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 18) {
                ForEach(HotKeyAction.allCases, id: \.rawValue) { action in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(action.title).font(.system(size: 12, weight: .medium))
                            Spacer(minLength: 12)
                            HotKeyRecorder(binding: hotkeys.bindings[action], feature: action.title,
                                onBinding: { hotkeys.setBinding($0, for: action) },
                                onRecording: { hotkeys.setRecording($0) })
                                .frame(width: 166, height: 28).disabled(!hotkeys.enabled)
                            Button { hotkeys.setBinding(nil, for: action) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain).help(L10n.tr("Clear Shortcut"))
                            .accessibilityLabel(L10n.tr("Clear Shortcut"))
                            .disabled(!hotkeys.enabled || hotkeys.bindings[action] == nil)
                        }
                        if let status = hotkeys.errors[action] {
                            Text(L10n.tr("This shortcut could not be registered (macOS error %d). Choose another combination.", status))
                                .font(.system(size: 10)).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if action != .focus { Divider() }
                }
            }
            .padding(18).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            if let message = hotkeys.validationMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange)
            }
            Text(L10n.tr("Click a shortcut, then press your key combination. Include Control (⌃) or Option (⌥). Press Escape to cancel or Delete to clear."))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.tr("Closed-lid mode uses your existing power permissions. Set up the On and Off shortcuts in the Do Not Disturb tab before using its hotkey."))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.tr("Restore Default Hotkeys"), action: hotkeys.restoreDefaults)
                .font(.system(size: 11))
            Spacer(minLength: 0)
            HStack {
                Text(L10n.tr("Hotkeys work while NonSleep is running."))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("Done"), action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .onDisappear { hotkeys.setRecording(false) }
    }
}

private struct HotKeyRecorder: NSViewRepresentable {
    let binding: HotKeyBinding?
    let feature: String
    let onBinding: (HotKeyBinding?) -> Void
    let onRecording: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.normalTitle = binding?.display ?? L10n.tr("Record Shortcut…")
        button.recordingTitle = L10n.tr("Press shortcut…")
        button.onBinding = onBinding
        button.onRecording = onRecording
        button.setAccessibilityLabel(L10n.tr("Shortcut for %@", feature))
        button.isEnabled = context.environment.isEnabled
        if !button.isEnabled { button.finishRecording() }
        button.title = button.recording ? button.recordingTitle : button.normalTitle
    }

    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) { button.finishRecording() }
}

private final class RecorderButton: NSButton {
    var normalTitle = ""
    var recordingTitle = ""
    var onBinding: ((HotKeyBinding?) -> Void)?
    var onRecording: ((Bool) -> Void)?
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        guard !recording else { finishRecording(); return }
        recording = true
        title = recordingTitle
        window?.makeFirstResponder(self)
        onRecording?(true)
    }

    func finishRecording() {
        guard recording else { return }
        recording = false
        title = normalTitle
        onRecording?(false)
    }

    override func resignFirstResponder() -> Bool { finishRecording(); return super.resignFirstResponder() }
    override func cancelOperation(_ sender: Any?) { finishRecording() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        guard !event.isARepeat else { return }
        let modifiers = HotKeyModifiers(eventFlags: event.modifierFlags)
        if event.keyCode == 53 && modifiers.isEmpty { finishRecording(); return }
        if event.keyCode == 51 && modifiers.isEmpty { onBinding?(nil) }
        else { onBinding?(HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)) }
        finishRecording()
    }
}
