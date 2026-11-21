import Foundation

/// Calendar date plus an optional intra-day release number: YYYY.MM.DD[.N].
public struct CalVer: Comparable, Hashable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int
    public let revision: Int
    public let prerelease: String?

    public init?(_ value: String) {
        let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
        guard raw.range(of: #"^[2-9][0-9]{3}\.[0-9]{2}\.[0-9]{2}(?:\.[1-9][0-9]*)?(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$"#,
                        options: .regularExpression) != nil else { return nil }
        let sections = raw.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let prerelease = sections.count == 2 ? String(sections[1]) : nil
        if let prerelease {
            guard !prerelease.isEmpty,
                  prerelease.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                      !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                  }) else { return nil }
        }
        let parts = sections[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (3...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let year = Int(parts[0]), (2000...9999).contains(year),
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]), (1...31).contains(day) else { return nil }
        let revision = parts.count == 4 ? Int(parts[3]) : 0
        guard let revision, revision >= 0, parts.count != 4 || revision > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
        self.revision = revision
        self.prerelease = prerelease
        guard raw == description else { return nil }
    }

    public var appVersion: String { String(format: "%04d.%02d.%02d", year, month, day) }
    public var description: String { appVersion + (revision > 0 ? ".\(revision)" : "") + (prerelease.map { "-" + $0 } ?? "") }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let a = [lhs.year, lhs.month, lhs.day, lhs.revision]
        let b = [rhs.year, rhs.month, rhs.day, rhs.revision]
        if a != b { return a.lexicographicallyPrecedes(b) }
        guard let left = lhs.prerelease else { return false }
        guard let right = rhs.prerelease else { return true }
        let leftParts = left.split(separator: "."), rightParts = right.split(separator: ".")
        for (l, r) in zip(leftParts, rightParts) where l != r {
            if let ln = Int(l), let rn = Int(r) { return ln < rn }
            if Int(l) != nil { return true }
            if Int(r) != nil { return false }
            return l < r
        }
        return leftParts.count < rightParts.count
    }

    public func isNewer(than installed: String) throws -> Bool {
        if let current = CalVer(installed) { return self > current }
        // Migrate existing 0.x / SemVer builds to the first calendar release.
        let legacy = installed.split(separator: ".", omittingEmptySubsequences: false)
        if legacy.count == 3, legacy.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
           let major = Int(legacy[0]), major < 2000 { return true }
        throw UpdateError.invalidInstalledVersion
    }
}
