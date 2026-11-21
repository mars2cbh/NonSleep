import AppKit
import Combine
import ServiceManagement

enum SettingsTab: Hashable { case general, focus, updates }
enum HelperState {
    case checking, notInstalled, ready, appUpdated, needsUpdate, unavailable
    var title: String {
        switch self {
        case .checking: return "상태 확인 중"
        case .notInstalled: return "등록되지 않음"
        case .ready: return "권한 승인됨 · 연결됨"
        case .appUpdated: return "앱 업데이트로 권한 갱신 필요"
        case .needsUpdate: return "다시 등록 필요"
        case .unavailable: return "연결 확인 필요"
        }
    }
}

@MainActor
protocol LoginServiceManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor
final class NativeLoginService: LoginServiceManaging {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() async throws { try await SMAppService.mainApp.unregister() }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var helperState: HelperState = .checking
    @Published private(set) var busy = false
    @Published private(set) var refreshing = false
    @Published var errorMessage: String?
    private let loginService: LoginServiceManaging

    init(loginService: LoginServiceManaging? = nil) {
        self.loginService = loginService ?? NativeLoginService()
        loginStatus = self.loginService.status
    }

    var loginEnabled: Bool { loginStatus == .enabled }
    var loginStatusTitle: String {
        switch loginStatus {
        case .enabled: return "켜짐"
        case .requiresApproval: return "시스템 설정에서 승인 필요"
        case .notFound: return "앱 등록을 확인할 수 없음"
        case .notRegistered: return "꺼짐"
        @unknown default: return "상태 미확인"
        }
    }

    func refreshLogin() { loginStatus = loginService.status }

    func refresh() async {
        refreshLogin()
        guard !busy, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await checkHelper()
    }

    private func checkHelper() async {
        switch HelperInstaller.inspect() {
        case .notInstalled: helperState = .notInstalled
        case .needsUpdate: helperState = .needsUpdate
        case .appUpdated: helperState = .appUpdated
        case .installed:
            do { try await HelperClient.ping(); helperState = .ready }
            catch { helperState = .unavailable }
        }
    }

    func setLoginEnabled(_ enabled: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false; refreshLogin() }
        do {
            if enabled {
                guard loginService.status != .enabled else { return }
                if loginService.status == .requiresApproval {
                    openLoginSettings()
                } else { try loginService.register() }
            } else if loginService.status != .notRegistered {
                try await loginService.unregister()
            }
        } catch { errorMessage = "로그인 자동 실행 설정을 변경하지 못했습니다. \(error.localizedDescription)" }
    }

    func installHelper() async {
        guard !busy, !refreshing else { return }
        busy = true
        defer { busy = false }
        do { try await HelperInstaller.install() }
        catch { errorMessage = "전원 도우미 등록을 완료하지 못했습니다. \(error.localizedDescription)" }
        await checkHelper()
    }

    func removeHelper() async {
        guard !busy, !refreshing else { return }
        busy = true
        defer { busy = false }
        do { try await HelperInstaller.uninstall() }
        catch { errorMessage = "전원 도우미 제거를 완료하지 못했습니다. \(error.localizedDescription)" }
        await checkHelper()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
