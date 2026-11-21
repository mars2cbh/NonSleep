import NonSleepCore
import AppKit
import Combine
import ServiceManagement

enum SettingsTab: Hashable { case general, focus, updates }
enum HelperState {
    case checking, notInstalled, ready, appUpdated, needsUpdate, unavailable
    var title: String {
        switch self {
        case .checking: return L10n.tr("Checking status…")
        case .notInstalled: return L10n.tr("Not registered")
        case .ready: return L10n.tr("Authorized · Connected")
        case .appUpdated: return L10n.tr("App updated · Renew approval")
        case .needsUpdate: return L10n.tr("Registration required again")
        case .unavailable: return L10n.tr("Connection needs attention")
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
        case .enabled: return L10n.tr("On")
        case .requiresApproval: return L10n.tr("Approval needed in System Settings")
        case .notFound: return L10n.tr("App registration could not be verified")
        case .notRegistered: return L10n.tr("Off")
        @unknown default: return L10n.tr("Status unknown")
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
        } catch { errorMessage = L10n.tr("Could not change launch-at-login settings. %@", error.localizedDescription) }
    }

    func installHelper() async {
        guard !busy, !refreshing else { return }
        busy = true
        defer { busy = false }
        do { try await HelperInstaller.install() }
        catch { errorMessage = L10n.tr("Could not register the power helper. %@", error.localizedDescription) }
        await checkHelper()
    }

    func removeHelper() async {
        guard !busy, !refreshing else { return }
        busy = true
        defer { busy = false }
        do { try await HelperInstaller.uninstall() }
        catch { errorMessage = L10n.tr("Could not remove the power helper. %@", error.localizedDescription) }
        await checkHelper()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
