import Foundation
import NonSleepCore

struct FocusShortcut: Identifiable, Equatable {
    let id: String
    let name: String
}

protocol FocusShortcutRunning {
    func list() async throws -> [FocusShortcut]
    func run(identifier: String) async throws
}

struct FocusService: FocusShortcutRunning {
    func list() async throws -> [FocusShortcut] {
        let output = try await Commands.checked("/usr/bin/shortcuts", ["list", "--show-identifiers"])
        return try Self.parse(output)
    }

    func run(identifier: String) async throws {
        _ = try await Commands.checked("/usr/bin/shortcuts", ["run", identifier], timeout: 120)
    }

    static func parse(_ output: String) throws -> [FocusShortcut] {
        try output.components(separatedBy: .newlines).filter { !$0.isEmpty }.map { line in
            guard line.hasSuffix(")"), let separator = line.range(of: " (", options: .backwards),
                  let uuid = UUID(uuidString: String(line[separator.upperBound...].dropLast())) else {
                throw AppError.message(L10n.tr("The shortcut list could not be read. Open Shortcuts, then refresh the list."))
            }
            return FocusShortcut(id: uuid.uuidString, name: String(line[..<separator.lowerBound]))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Old releases saved names. Only migrate an unambiguous match; duplicate
    /// names must never silently run a different shortcut.
    static func resolve(_ selection: String, in shortcuts: [FocusShortcut]) throws -> FocusShortcut {
        let matches: [FocusShortcut]
        if let uuid = UUID(uuidString: selection) {
            matches = shortcuts.filter { $0.id == uuid.uuidString }
        } else { matches = shortcuts.filter { $0.name == selection } }
        guard matches.count == 1, let shortcut = matches.first else {
            throw AppError.message(L10n.tr("The selected shortcut is missing or has a duplicate name. Refresh the list and select it again."))
        }
        return shortcut
    }
}
