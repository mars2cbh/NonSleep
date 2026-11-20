import Foundation
import Security

public enum HelperConfiguration {
    public static let serviceName = "dev.nonsleep.helper"
    public static let executablePath = "/Library/PrivilegedHelperTools/dev.nonsleep.helper"
    public static let clientRequirementPath = "/Library/PrivilegedHelperTools/dev.nonsleep.helper.client-requirement"
    public static let plistPath = "/Library/LaunchDaemons/dev.nonsleep.helper.plist"
    public static let version = 1

    public static func launchDaemonPlist() throws -> String {
        let values: [String: Any] = [
            "Label": serviceName,
            "ProgramArguments": [executablePath],
            "MachServices": [serviceName: true],
            "UserName": "root",
            "AssociatedBundleIdentifiers": ["dev.nonsleep.mac"],
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        return String(decoding: data, as: UTF8.self)
    }
}

/// The privileged interface deliberately accepts only a boolean, never commands or paths.
@objc(NonSleepHelperProtocol)
public protocol NonSleepHelperProtocol {
    func ping(withReply reply: @escaping (Int) -> Void)
    func setSleepDisabled(_ enabled: Bool, withReply reply: @escaping (String?) -> Void)
}

public enum SigningIdentity {
    public static func requirement(at url: URL) throws -> String {
        var code: SecStaticCode?
        try check(SecStaticCodeCreateWithPath(url as CFURL, [], &code))
        guard let code else { throw failure(errSecCSUnsigned) }
        try check(SecStaticCodeCheckValidity(code, [], nil))
        var requirement: SecRequirement?
        try check(SecCodeCopyDesignatedRequirement(code, [], &requirement))
        guard let requirement else { throw failure(errSecCSUnsigned) }
        var text: CFString?
        try check(SecRequirementCopyString(requirement, [], &text))
        guard let text else { throw failure(errSecCSUnsigned) }
        return text as String
    }

    public static func validateRequirement(_ text: String) throws {
        var requirement: SecRequirement?
        try check(SecRequirementCreateWithString(text as CFString, [], &requirement))
    }

    private static func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "앱 코드 서명을 확인하지 못했습니다. 앱을 다시 빌드하거나 설치해 주세요. (\(status))"
        ])
    }
}
