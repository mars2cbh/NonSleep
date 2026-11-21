import Foundation
import NonSleepCore
import OSLog

@main
enum NonSleepHelper {
    static func main() {
        guard geteuid() == 0 else { exit(EX_NOPERM) }
        do {
            // Both this configuration and the executable are installed root-owned.
            let attributes = try FileManager.default.attributesOfItem(atPath: HelperConfiguration.clientRequirementPath)
            guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
                  let mode = attributes[.posixPermissions] as? NSNumber,
                  mode.intValue & 0o022 == 0,
                  attributes[.type] as? FileAttributeType == .typeRegular else { exit(EX_CONFIG) }
            let requirement = try String(contentsOfFile: HelperConfiguration.clientRequirementPath, encoding: .utf8)
            try SigningIdentity.validateRequirement(requirement)
            let delegate = HelperDelegate(requirement: requirement)
            let listener = NSXPCListener(machServiceName: HelperConfiguration.serviceName)
            listener.delegate = delegate
            listener.resume()
            RunLoop.current.run()
            withExtendedLifetime(delegate) {}
        } catch {
            Logger(subsystem: HelperConfiguration.serviceName, category: "startup")
                .error("Unable to start helper: \(error.localizedDescription, privacy: .public)")
            exit(EX_CONFIG)
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let requirement: String
    private let service = PowerControl()

    init(requirement: String) { self.requirement = requirement }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Enforced for every message by XPC; no PID-based identity check or race.
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: NonSleepHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

final class PowerControl: NSObject, NonSleepHelperProtocol {
    private let queue = DispatchQueue(label: "dev.nonsleep.helper.power")

    func ping(withReply reply: @escaping (Int) -> Void) { reply(HelperConfiguration.version) }

    func setSleepDisabled(_ enabled: Bool, withReply reply: @escaping (String?) -> Void) {
        queue.async {
            do {
                _ = try Self.pmset(["-a", "disablesleep", enabled ? "1" : "0"])
                let actual = try PowerSettings.sleepDisabled(from: Self.pmset(["-g"]))
                guard actual == enabled else {
                    throw NSError(domain: HelperConfiguration.serviceName, code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: L10n.tr("The power setting change could not be verified.")])
                }
                reply(nil)
            } catch { reply(error.localizedDescription) }
        }
    }

    private static func pmset(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timeout)
        // These two fixed pmset commands have small output; drain before waiting.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: HelperConfiguration.serviceName, code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: L10n.tr("The power setting operation failed.")])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
