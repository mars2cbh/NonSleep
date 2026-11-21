import Foundation
import NonSleepCore

enum HelperInstallation {
    case notInstalled, installed, appUpdated, needsUpdate
}

enum HelperInstaller {
    static func inspect() -> HelperInstallation {
        let manager = FileManager.default
        let paths = [HelperConfiguration.executablePath, HelperConfiguration.clientRequirementPath, HelperConfiguration.plistPath]
        guard paths.contains(where: { manager.fileExists(atPath: $0) }) else { return .notInstalled }
        do {
            for path in paths {
                let attributes = try manager.attributesOfItem(atPath: path)
                guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
                      let permissions = attributes[.posixPermissions] as? NSNumber,
                      permissions.intValue & 0o022 == 0,
                      attributes[.type] as? FileAttributeType == .typeRegular else { return .needsUpdate }
            }
            let expectedClient = try SigningIdentity.requirement(at: Bundle.main.bundleURL)
            let actualClient = try String(contentsOfFile: HelperConfiguration.clientRequirementPath, encoding: .utf8)
            guard try SigningIdentity.requirement(at: HelperClient.bundledExecutable)
                    == SigningIdentity.requirement(at: URL(fileURLWithPath: HelperConfiguration.executablePath)) else {
                return .needsUpdate
            }
            guard expectedClient == actualClient else { return .appUpdated }
            return .installed
        } catch { return .needsUpdate }
    }

    static func install() async throws {
        let manager = FileManager.default
        let stage = manager.temporaryDirectory.appendingPathComponent("NonSleep-install-\(UUID().uuidString)")
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: stage) }

        // The user-owned copy is only an input. Root takes its own snapshot and
        // verifies the exact expected signature before installing executable code.
        let executable = stage.appendingPathComponent("helper")
        try manager.copyItem(at: HelperClient.bundledExecutable, to: executable)
        let helperRequirement = try SigningIdentity.requirement(at: HelperClient.bundledExecutable)
        let requirement = try SigningIdentity.requirement(at: Bundle.main.bundleURL)
        let plist = try HelperConfiguration.launchDaemonPlist()

        let quote = PowerSettings.shellQuote
        let script = """
        set -eu
        /usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools
        NONSLEEP_ROOT_STAGE=$(/usr/bin/mktemp -d /Library/PrivilegedHelperTools/.nonsleep-install.XXXXXX)
        trap '/bin/rm -rf "$NONSLEEP_ROOT_STAGE"' EXIT
        /usr/bin/install -o root -g wheel -m 0755 \(quote(executable.path)) "$NONSLEEP_ROOT_STAGE/helper"
        /usr/bin/codesign --verify --strict --test-requirement \(quote("=" + helperRequirement)) "$NONSLEEP_ROOT_STAGE/helper"
        /usr/bin/printf '%s' \(quote(requirement)) > "$NONSLEEP_ROOT_STAGE/client-requirement"
        /usr/bin/printf '%s' \(quote(plist)) > "$NONSLEEP_ROOT_STAGE/helper.plist"
        if /bin/launchctl print system/\(HelperConfiguration.serviceName) >/dev/null 2>&1; then
            /bin/launchctl bootout system/\(HelperConfiguration.serviceName)
        fi
        /usr/bin/install -o root -g wheel -m 0755 "$NONSLEEP_ROOT_STAGE/helper" \(quote(HelperConfiguration.executablePath))
        /usr/bin/install -o root -g wheel -m 0644 "$NONSLEEP_ROOT_STAGE/client-requirement" \(quote(HelperConfiguration.clientRequirementPath))
        /usr/bin/install -o root -g wheel -m 0644 "$NONSLEEP_ROOT_STAGE/helper.plist" \(quote(HelperConfiguration.plistPath))
        /bin/launchctl bootstrap system \(quote(HelperConfiguration.plistPath))
        """
        try await runPrivileged(script)
        guard inspect() == .installed else {
            throw AppError.message(L10n.tr("The power helper installation could not be verified. Register it again in Settings."))
        }
        try await HelperClient.ping()
    }

    static func uninstall() async throws {
        let quote = PowerSettings.shellQuote
        let script = """
        set -eu
        if /bin/launchctl print system/\(HelperConfiguration.serviceName) >/dev/null 2>&1; then
            /bin/launchctl bootout system/\(HelperConfiguration.serviceName)
        fi
        /bin/rm -f \(quote(HelperConfiguration.plistPath)) \(quote(HelperConfiguration.executablePath)) \(quote(HelperConfiguration.clientRequirementPath))
        """
        try await runPrivileged(script)
        guard inspect() == .notInstalled else {
            throw AppError.message(L10n.tr("The power helper removal could not be verified."))
        }
    }

    private static func runPrivileged(_ script: String) async throws {
        let appleScript = "do shell script \(PowerSettings.appleScriptString(script)) with administrator privileges"
        _ = try await Commands.checked("/usr/bin/osascript", ["-e", appleScript], timeout: 120)
    }
}
