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

    var body: some View {
        TabView(selection: $model.settingsTab) {
            general.tabItem { Label("일반", systemImage: "gearshape") }.tag(SettingsTab.general)
            FocusSetup(model: model, onDone: onClose).tabItem { Label("방해 금지", systemImage: "moon") }.tag(SettingsTab.focus)
            UpdateSettingsView(updates: model.updates, onClose: onClose)
                .tabItem { Label("업데이트", systemImage: "arrow.triangle.2.circlepath") }.tag(SettingsTab.updates)
        }
        .padding(.top, 12)
        .frame(width: 542, height: 700)
        .task { await settings.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await settings.refresh() }
        }
        .alert("설정을 변경하지 못했어요", isPresented: Binding(
            get: { settings.errorMessage != nil }, set: { if !$0 { settings.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { settings.errorMessage = nil }
        } message: { Text(settings.errorMessage ?? "") }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.circle.fill").font(.system(size: 34)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NonSleep 설정").font(.system(size: 21, weight: .semibold))
                    Text("자동 실행과 전원 권한을 한곳에서 관리하세요.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                Toggle(isOn: Binding(get: { settings.loginEnabled }, set: { enabled in
                    Task { await settings.setLoginEnabled(enabled) }
                })) {
                    Label("로그인 시 자동 실행", systemImage: "power")
                        .font(.system(size: 13, weight: .semibold))
                }
                .toggleStyle(.switch).disabled(settings.busy || model.busy != nil)
                Text("Mac에 로그인하면 메뉴 막대에 NonSleep을 실행합니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Text(settings.loginStatusTitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button("로그인 항목 열기", action: settings.openLoginSettings).font(.system(size: 11))
                }
                Text("앱을 응용 프로그램 폴더에 둔 뒤 설정하면 편리합니다.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(17).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("덮개 잠자기 권한", systemImage: "lock.shield")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if settings.busy || settings.refreshing { ProgressView().controlSize(.small) }
                }
                Text("전원 도우미를 등록할 때 관리자 인증을 한 번 받습니다. 등록 후에는 덮개 기능을 켜거나 끌 때, 앱 종료 시 복원할 때도 반복 인증 없이 사용할 수 있습니다.")
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
                    Button("상태 확인") { Task { await settings.refresh() } }
                        .disabled(settings.busy || settings.refreshing)
                    Spacer()
                    if settings.helperState != .notInstalled && settings.helperState != .checking {
                        Button("제거…") { Task { await settings.removeHelper() } }
                            .disabled(settings.busy || settings.refreshing || model.busy != nil || model.lid || model.recovery != nil)
                    }
                }
                .font(.system(size: 11))
                if model.lid || model.recovery != nil {
                    Text("도우미를 제거하려면 덮개 잠자기 방지를 끄고 전원 설정을 복원해 주세요.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Divider()
                Text(settings.helperState == .appUpdated
                     ? "기존 도우미는 설치되어 있습니다. 앱을 새로 빌드해 서명이 바뀌었으므로 한 번만 권한 승인을 갱신해 주세요. 앱을 껐다 켜는 것만으로는 다시 승인하지 않습니다."
                     : "도우미는 잠자기 설정만 변경하며 인증 비밀번호를 저장하지 않습니다. 승인은 앱 재실행 후에도 유지됩니다. 개발용 앱을 새로 빌드하면 권한 갱신이 필요할 수 있습니다.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

            Text("도우미를 등록하지 않아도 덮개 기능은 매번 관리자 인증을 받아 사용할 수 있습니다. 방해 금지 단축어는 위의 ‘방해 금지’ 탭에서 연결하세요.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Text("NonSleep \(model.updates.installedVersion)")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("완료", action: onClose).keyboardShortcut(.defaultAction)
                    .disabled(settings.busy)
            }
        }
        .padding(26)
    }

    private var helperActionTitle: String {
        switch settings.helperState {
        case .notInstalled: return "관리자 권한 받기…"
        case .appUpdated: return "업데이트 권한 승인…"
        default: return "도우미 다시 등록…"
        }
    }
}
