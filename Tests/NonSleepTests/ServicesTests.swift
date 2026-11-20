import XCTest
import IOKit.pwr_mgt
@testable import NonSleep

final class ServicesTests: XCTestCase {
    @MainActor
    func testSleepAssertionsAreCreatedOnceAndReleased() throws {
        let service = AwakeService()
        defer { service.disable() }
        try service.enable()
        try service.enable()
        let active = try ownAssertions()
        XCTAssertEqual(active.count, 2, "Repeated ON must not leak assertions")
        XCTAssertEqual(Set(active.compactMap { $0[kIOPMAssertionTypeKey] as? String }),
                       Set(["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep"]))
        service.disable()
        XCTAssertTrue(try ownAssertions().isEmpty)
        service.disable()
    }

    func testProcessArgumentsArePassedLiterally() async throws {
        let literal = "quote' \" $(echo unwanted) `echo unwanted` \\ 한글"
        let output = try await Commands.checked("/usr/bin/printf", ["%s", literal])
        XCTAssertEqual(output, literal)
    }

    func testFailedProcessIsNotReportedAsSuccess() async {
        do {
            _ = try await Commands.checked("/usr/bin/false", [])
            XCTFail("A failed command must throw")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }

    func testHangingCommandTimesOut() async throws {
        let start = Date()
        let result = try await Commands.run("/bin/sleep", ["10"], timeout: 0.1)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    private func ownAssertions() throws -> [[String: Any]] {
        var dictionary: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&dictionary)
        guard status == kIOReturnSuccess, let dictionary else {
            throw AppError.message("Cannot read IOKit assertions: \(status)")
        }
        let all = dictionary.takeRetainedValue() as NSDictionary
        let assertions = all[NSNumber(value: getpid())] as? [[String: Any]] ?? []
        return assertions.filter { ($0[kIOPMAssertionNameKey] as? String)?.hasPrefix("NonSleep ·") == true }
    }
}
