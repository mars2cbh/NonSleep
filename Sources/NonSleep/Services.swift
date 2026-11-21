import AppKit
import IOKit.pwr_mgt
import NonSleepCore

struct CommandResult {
    let output: String
    let error: String
    let status: Int32
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum Commands {
    /// Output goes to temporary files so long shortcut listings cannot fill a pipe.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let outURL = directory.appendingPathComponent("stdout")
            let errURL = directory.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
            let out = try FileHandle(forWritingTo: outURL)
            let err = try FileHandle(forWritingTo: errURL)
            defer { try? out.close(); try? err.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = out
            process.standardError = err
            try process.run()
            let expiration = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: expiration)
            process.waitUntilExit()
            expiration.cancel()
            return CommandResult(
                output: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
                error: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "",
                status: process.terminationStatus
            )
        }.value
    }

    static func checked(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) async throws -> String {
        let result = try await run(executable, arguments, timeout: timeout)
        guard result.status == 0 else {
            if result.error.contains("-128") {
                throw AppError.message(L10n.tr("Administrator authentication was canceled. No settings were changed."))
            }
            let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppError.message(detail.isEmpty ? L10n.tr("The action could not be completed. Please try again.") : String(detail.prefix(600)))
        }
        return result.output
    }
}

@MainActor
final class AwakeService {
    private var assertions: [IOPMAssertionID] = []

    func enable() throws {
        guard assertions.isEmpty else { return }
        do {
            for type in [kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventUserIdleDisplaySleep] {
                var identifier: IOPMAssertionID = 0
                let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    L10n.tr("NonSleep · Keep Awake was enabled by the user") as CFString, &identifier)
                guard result == kIOReturnSuccess else {
                    throw AppError.message(L10n.tr("Could not enable Keep Awake. (IOKit %d)", result))
                }
                assertions.append(identifier)
            }
        } catch {
            disable()
            throw error
        }
    }

    func disable() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
    }
}

enum LidService {
    static func read() async throws -> Bool {
        try PowerSettings.sleepDisabled(from: await Commands.checked("/usr/bin/pmset", ["-g"]))
    }

    static func set(_ enabled: Bool) async throws {
        switch HelperInstaller.inspect() {
        case .installed:
            try await HelperClient.setSleepDisabled(enabled)
        case .appUpdated:
            throw AppError.message(L10n.tr("This app was updated and the power helper needs renewed approval. Choose Settings → General → Approve Update once. Restarting the same app does not require approval again."))
        case .needsUpdate:
            throw AppError.message(L10n.tr("Register the power helper for this app version in Settings → General → Closed-Lid Permission."))
        case .notInstalled:
            let command = "/usr/bin/pmset -a disablesleep \(enabled ? 1 : 0)"
            let script = "do shell script \(PowerSettings.appleScriptString(command)) with administrator privileges"
            _ = try await Commands.checked("/usr/bin/osascript", ["-e", script], timeout: 120)
        }
        guard try await read() == enabled else {
            throw AppError.message(L10n.tr("The closed-lid sleep setting could not be verified. This Mac or macOS version may not support it."))
        }
    }
}
