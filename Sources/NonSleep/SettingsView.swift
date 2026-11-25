import NonSleepCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    let onClose: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.settings = model.settings
        self.onClose = onClose
    }

    @ObservedObject private var language = LanguageSettings.shared

    var body: some View {
        TabView(selection: $model.settingsTab) {
            general.tabItem { Label(L10n.tr("General"), systemImage: "gearshape") }.tag(SettingsTab.general)
            FocusSetup(model: model, onDone: onClose).tabItem { Label(L10n.tr("Do Not Disturb"), systemImage: "moon") }.tag(SettingsTab.focus)
            HotKeySettingsView(hotkeys: model.hotkeys, onClose: onClose)
                .tabItem { Label(L10n.tr("Hotkeys"), systemImage: "keyboard") }.tag(SettingsTab.hotkeys)
            UpdateSettingsView(updates: model.updates, onClose: onClose)
                .tabItem { Label(L10n.tr("Updates"), systemImage: "arrow.triangle.2.circlepath") }.tag(SettingsTab.updates)
        }
        .environment(\.locale, language.locale)
        .padding(.top, 12)
        .frame(width: 542, height: 700)
        .task { await settings.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await settings.refresh() }
        }
        .alert(L10n.tr("Couldn’t Change Settings"), isPresented: Binding(
            get: { settings.errorMessage != nil }, set: { if !$0 { settings.errorMessage = nil } }
        )) {
            Button(L10n.tr("OK"), role: .cancel) { settings.errorMessage = nil }
        } message: { Text(settings.errorMessage ?? "") }
    }

    private var general: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape.circle.fill").font(.system(size: 34)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("NonSleep Settings")).font(.system(size: 21, weight: .semibold))
                        Text(L10n.tr("Manage startup and power permissions in one place."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Picker(L10n.tr("Language"), selection: $language.selection) {
                        Text(L10n.tr("Follow System Settings")).tag(AppLanguage.system)
                        Text("English").tag(AppLanguage.english)
                        Text("한국어").tag(AppLanguage.korean)
                    }
                    .font(.system(size: 12))
                    Text(L10n.tr("Some system dialogs use the new language after restarting the app."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 11) {
                    Toggle(isOn: Binding(get: { settings.loginEnabled }, set: { enabled in
                        Task { await settings.setLoginEnabled(enabled) }
                    })) {
                        Label(L10n.tr("Launch at login"), systemImage: "power")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .toggleStyle(.switch).disabled(settings.busy || model.busy != nil)
                    Text(L10n.tr("Start NonSleep in the menu bar when you log in."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Text(settings.loginStatusTitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.tr("Open Login Items"), action: settings.openLoginSettings).font(.system(size: 11))
                    }
                    Text(L10n.tr("Move the app to Applications before enabling this option."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(17).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label(L10n.tr("Closed-Lid Permission"), systemImage: "lock.shield")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if settings.busy || settings.refreshing { ProgressView().controlSize(.small) }
                    }
                    Text(L10n.tr("Authenticate once to register the power helper. Then toggle closed-lid mode and restore power settings on quit without repeated authentication."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(settings.helperState.title, systemImage: settings.helperState == .ready ? "checkmark.circle.fill" : "info.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(settings.helperState == .ready ? Color.green : .secondary)
                    HStack {
                        Button(helperActionTitle) {
                            Task { await settings.installHelper() }
                        }
                        .disabled(settings.busy || settings.refreshing || model.busy != nil)
                        Button(L10n.tr("Check Status")) { Task { await settings.refresh() } }
                            .disabled(settings.busy || settings.refreshing)
                        Spacer()
                        if settings.helperState != .notInstalled && settings.helperState != .checking {
                            Button(L10n.tr("Remove…")) { Task { await settings.removeHelper() } }
                                .disabled(settings.busy || settings.refreshing || model.busy != nil || model.lid || model.recovery != nil)
                        }
                    }
                    .font(.system(size: 11))
                    if model.lid || model.recovery != nil {
                        Text(L10n.tr("Turn off closed-lid mode and restore power settings before removing the helper."))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text(settings.helperState == .appUpdated
                         ? L10n.tr("The helper is still installed. This new build has a different signature, so renew approval once. Restarting the same build does not require approval again.")
                         : L10n.tr("The helper only changes sleep settings and never stores your password. Approval survives app restarts. A new development build may need renewed approval."))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(17).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

                Text(L10n.tr("Without the helper, closed-lid mode asks for authentication each time. Connect Focus shortcuts in the Do Not Disturb tab."))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Text("NonSleep \(model.updates.installedVersion)")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Button(L10n.tr("Done"), action: onClose).keyboardShortcut(.defaultAction)
                        .disabled(settings.busy)
                }
            }
            .padding(26)
        }
    }

    private var helperActionTitle: String {
        switch settings.helperState {
        case .notInstalled: return L10n.tr("Authorize Helper…")
        case .appUpdated: return L10n.tr("Approve Update…")
        default: return L10n.tr("Register Helper Again…")
        }
    }
}
