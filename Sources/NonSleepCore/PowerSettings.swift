import Foundation

public enum PowerSettings {
    /// An omitted SleepDisabled key means the system default: sleep is allowed.
    /// Reject unexpected output instead of incorrectly displaying an OFF state.
    public static func sleepDisabled(from output: String) throws -> Bool {
        let lines = output.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.contains("System-wide power settings:") }) else {
            throw SettingsError.unreadable
        }
        for line in lines {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.first == "SleepDisabled" else { continue }
            guard parts.count == 2, let value = Int(parts[1]), (0...1).contains(value) else {
                throw SettingsError.unreadable
            }
            return value == 1
        }
        return false
    }

    public static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum SettingsError: LocalizedError {
    case unreadable
    public var errorDescription: String? { L10n.tr("The macOS power settings could not be read. Please try again.") }
}

/// Written before a privileged mutation, and removed only after verified restoration.
/// Survives a forced quit or power loss so the next launch can offer recovery.
public struct LidRecovery: Codable, Equatable {
    public let originalDisabled: Bool
    public init(originalDisabled: Bool) { self.originalDisabled = originalDisabled }
}
