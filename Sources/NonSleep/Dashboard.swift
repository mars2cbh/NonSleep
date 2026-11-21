import NonSleepCore
import SwiftUI

private let leaf = Color(red: 0.23, green: 0.49, blue: 0.37)

struct Dashboard: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private var background: Color {
        scheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.11) : Color(red: 0.96, green: 0.96, blue: 0.93)
    }

    @ObservedObject private var language = LanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            hero
            VStack(spacing: 10) {
                FeatureRow(icon: "sun.max", title: L10n.tr("Keep Awake"), tag: model.awake ? L10n.tr("Active") : nil,
                    detail: L10n.tr("Keep your Mac and display awake."),
                    note: model.lid && !model.awake ? L10n.tr("Closed-lid mode is still preventing system sleep.") : nil,
                    isOn: Binding(get: { model.awake }, set: { model.setAwake($0) }),
                    busy: false, disabled: model.busy != nil, activeColor: Color(nsColor: StatusAppearance.awake.color))

                FeatureRow(icon: "laptopcomputer", title: L10n.tr("Stay Awake with Lid Closed"),
                    tag: model.lidKnown ? (model.lid ? L10n.tr("Active") : L10n.tr("Admin access")) : L10n.tr("Checking…"),
                    detail: L10n.tr("Keep working with your MacBook lid closed."),
                    note: L10n.tr("Also prevents system sleep. Behavior may vary by Mac and macOS version."),
                    isOn: Binding(get: { model.lid }, set: { value in Task { await model.setLid(value) } }),
                    busy: model.busy == "lid", disabled: model.busy != nil || !model.lidKnown,
                    activeColor: Color(nsColor: StatusAppearance.lid.color))

                FeatureRow(icon: "moon", title: L10n.tr("Do Not Disturb"),
                    tag: !model.focusConfigured ? L10n.tr("Setup needed") : (model.focusRequest == nil ? L10n.tr("Status unknown") : L10n.tr("Shortcut ran")),
                    detail: L10n.tr("Pause notifications and focus on your work."),
                    note: model.focusConfigured ? L10n.tr("Shows the last shortcut request. Changes made in macOS are not reflected here.") : L10n.tr("Connect separate On and Off shortcuts to get started."),
                    isOn: Binding(get: { model.focusRequest == true }, set: { value in Task { await model.setFocus(value) } }),
                    busy: model.busy == "focus", disabled: model.busy != nil,
                    activeColor: Color(nsColor: StatusAppearance.focus.color))
                .contextMenu {
                    Button(L10n.tr("Turn On Do Not Disturb")) { Task { await model.setFocus(true) } }
                    Button(L10n.tr("Turn Off Do Not Disturb")) { Task { await model.setFocus(false) } }
                    Divider()
                    Button(L10n.tr("Shortcut Settings…")) { model.openSettings(.focus) }
                }
            }

            if model.recovery != nil {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(leaf)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.tr("Power settings can be restored")).font(.system(size: 12, weight: .semibold))
                        Text(L10n.tr("Previous power settings are restored on quit. After a forced quit, restore them here."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(L10n.tr("Restore")) { Task { await model.restoreLid() } }
                        .font(.system(size: 11, weight: .medium)).disabled(model.busy != nil || !model.lidKnown)
                }
                .padding(12).background(leaf.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            footer
        }
        .padding(26)
        .frame(width: 466)
        .background(background)
        .tint(leaf)
        .environment(\.locale, language.locale)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .alert(L10n.tr("Couldn’t Complete Action"), isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(L10n.tr("OK"), role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: model.statusAppearance.symbolName)
                    .foregroundStyle(Color(nsColor: model.statusAppearance.color))
                Text("NonSleep").font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Spacer()
            Text("YOUR MAC, AWAKE.")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.3).foregroundStyle(.secondary)
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.tr("Your Mac, awake.\nYour focus, uninterrupted."))
                    .font(.system(size: 27, weight: .semibold)).tracking(-1)
                    .lineSpacing(3).lineLimit(2).minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Circle().fill(model.activeCount > 0 ? leaf : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(model.activeCount > 0 ? L10n.tr("Enabled features: %d", model.activeCount) : L10n.tr("Turn on the features you need"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(leaf.opacity(0.06)).frame(width: 100, height: 100)
                Circle().stroke(leaf.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: 88, height: 88)
                Image(systemName: model.activeCount > 0 ? "sun.max" : "sun.haze")
                    .font(.system(size: 42, weight: .ultraLight)).foregroundStyle(leaf)
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 9)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 10)).padding(.top, 1)
                Text(L10n.tr("Quitting releases sleep prevention. Do Not Disturb stays on, and notification exceptions follow your Focus settings."))
                    .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
            HStack {
                Button { model.openSettings() } label: {
                    Label(L10n.tr("Settings"), systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").accessibilityLabel(L10n.tr("Refresh power status"))
                }
                .buttonStyle(.plain).disabled(model.busy != nil)
                Button(L10n.tr("Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.plain).padding(.leading, 12).disabled(model.busy != nil)
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let tag: String?
    let detail: String
    let note: String?
    @Binding var isOn: Bool
    let busy: Bool
    let disabled: Bool
    let activeColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isOn ? activeColor : .secondary)
                .frame(width: 36, height: 36)
                .background(activeColor.opacity(isOn ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let tag {
                        Text(tag).font(.system(size: 8, weight: .medium))
                            .foregroundStyle(isOn ? activeColor : .secondary)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(activeColor.opacity(0.07), in: Capsule())
                    }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                if let note {
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if busy {
                ProgressView().controlSize(.small).frame(width: 34, height: 22)
                    .accessibilityLabel(L10n.tr("Changing %@", title))
            } else {
                Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(disabled).accessibilityLabel(title)
            }
        }
        .padding(15)
        .tint(activeColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.primary.opacity(0.04)))
    }
}
