import AppKit
import Combine
import NonSleepCore
import Sparkle

@MainActor
final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    enum Phase { case idle, checking, noRelease, upToDate, available, installing, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var candidate: UpdateCandidate?
    @Published private(set) var message: String?
    @Published private(set) var lastChecked: Date?
    @Published var automaticallyChecks: Bool {
        didSet {
            defaults.set(automaticallyChecks, forKey: "automaticallyChecksForReleases")
            if automaticallyChecks { Task { await checkIfNeeded() } }
        }
    }
    let installedVersion: String
    private let defaults: UserDefaults
    private let client: GitHubUpdateClient
    private var timer: Timer?
    private var sparkleStarted = false
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    private let checkInterval: TimeInterval = 6 * 60 * 60

    init(defaults: UserDefaults = .standard, client: GitHubUpdateClient = GitHubUpdateClient()) {
        self.defaults = defaults
        self.client = client
        installedVersion = Bundle.main.object(forInfoDictionaryKey: "NonSleepReleaseVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
        automaticallyChecks = defaults.object(forKey: "automaticallyChecksForReleases") as? Bool ?? true
        lastChecked = defaults.object(forKey: "lastReleaseCheck") as? Date
        super.init()
    }

    var isBusy: Bool { phase == .checking || phase == .installing }
    var canInstall: Bool { candidate != nil && !isBusy }
    var statusText: String {
        switch phase {
        case .idle: return "GitHub의 새 Release를 확인할 수 있습니다."
        case .checking: return "GitHub에서 새 버전을 확인하고 있습니다…"
        case .noRelease: return "아직 공개된 정식 Release가 없습니다."
        case .upToDate: return "최신 버전을 사용하고 있습니다."
        case .available: return "새 버전 \(candidate?.version.description ?? "")을 사용할 수 있습니다."
        case .installing: return "업데이트 창에서 다운로드와 설치를 진행해 주세요."
        case .failed: return message ?? "업데이트를 확인하지 못했습니다."
        }
    }

    static var architecture: UpdateArchitecture {
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }

    func startAutomaticChecks() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfNeeded() }
        }
        Task { await checkIfNeeded() }
    }

    private func checkIfNeeded() async {
        guard automaticallyChecks else { return }
        let lastAttempt = defaults.object(forKey: "lastReleaseCheckAttempt") as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAttempt) >= checkInterval else { return }
        await checkNow()
    }

    func checkNow() async {
        guard !isBusy else { return }
        phase = .checking
        message = nil
        defaults.set(Date(), forKey: "lastReleaseCheckAttempt")
        do {
            let result = try await client.check(installedVersion: installedVersion, architecture: Self.architecture)
            candidate = nil
            switch result {
            case .noPublishedRelease: phase = .noRelease
            case .upToDate: phase = .upToDate
            case .available(let update): candidate = update; phase = .available
            }
            lastChecked = Date()
            defaults.set(lastChecked, forKey: "lastReleaseCheck")
        } catch {
            candidate = nil
            message = error.localizedDescription
            phase = .failed
        }
    }

    func downloadAndInstall() {
        guard canInstall else { return }
        do {
            guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                  Data(base64Encoded: key)?.count == 32 else {
                throw AppError.message("업데이트 검증 키가 없는 빌드입니다. 공식 Release의 앱을 사용해 주세요.")
            }
            if !sparkleStarted {
                controller.updater.automaticallyChecksForUpdates = false
                controller.updater.automaticallyDownloadsUpdates = false
                try controller.updater.start()
                sparkleStarted = true
            }
            guard controller.updater.canCheckForUpdates else { return }
            phase = .installing
            NSApp.activate(ignoringOtherApps: true)
            controller.checkForUpdates(nil)
        } catch {
            message = error.localizedDescription
            phase = .failed
        }
    }

    @objc(updaterShouldPromptForPermissionToCheckForUpdates:)
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) throws {
        guard let candidate,
              updateItem.fileURL == candidate.archiveURL,
              updateItem.displayVersionString == candidate.version.description else {
            throw AppError.message("GitHub에서 확인한 버전과 설치 정보가 일치하지 않습니다. 다시 확인해 주세요.")
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? { candidate?.appcastURL.absoluteString }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            let value = error as NSError
            if value.domain == SUSparkleErrorDomain && value.code == 4007 {
                phase = candidate == nil ? .idle : .available
            } else {
                message = error.localizedDescription
                phase = .failed
            }
        } else if phase == .installing {
            phase = candidate == nil ? .idle : .available
        }
    }
}
