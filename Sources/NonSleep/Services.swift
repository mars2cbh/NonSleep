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
                throw AppError.message("관리자 인증을 취소했습니다. 설정을 변경하지 않았습니다.")
            }
            let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppError.message(detail.isEmpty ? "작업을 완료하지 못했습니다. 다시 시도해 주세요." : String(detail.prefix(600)))
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
                    "NonSleep · 사용자가 잠자기 방지를 켰습니다" as CFString, &identifier)
                guard result == kIOReturnSuccess else {
                    throw AppError.message("잠자기 방지를 시작하지 못했습니다. (IOKit \(result))")
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
            throw AppError.message("앱이 업데이트되어 전원 도우미의 권한 승인을 갱신해야 합니다. 설정 → 일반 → 업데이트 권한 승인에서 한 번 승인해 주세요. 같은 앱의 재실행에는 갱신이 필요하지 않습니다.")
        case .needsUpdate:
            throw AppError.message("전원 도우미를 현재 앱 버전으로 다시 등록해야 합니다. 설정 → 일반 → 덮개 잠자기 권한에서 등록해 주세요.")
        case .notInstalled:
            let command = "/usr/bin/pmset -a disablesleep \(enabled ? 1 : 0)"
            let script = "do shell script \(PowerSettings.appleScriptString(command)) with administrator privileges"
            _ = try await Commands.checked("/usr/bin/osascript", ["-e", script], timeout: 120)
        }
        guard try await read() == enabled else {
            throw AppError.message("이 Mac에서 덮개 잠자기 설정 변경을 확인하지 못했습니다. macOS 또는 기기에 따라 지원되지 않을 수 있습니다.")
        }
    }
}
