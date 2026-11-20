import XCTest
@testable import NonSleepCore

final class PowerSettingsTests: XCTestCase {
    func testSleepDisabledReadback() throws {
        XCTAssertTrue(try PowerSettings.sleepDisabled(from: "System-wide power settings:\n SleepDisabled  1\nCurrently in use:\n sleep 0"))
        XCTAssertFalse(try PowerSettings.sleepDisabled(from: "System-wide power settings:\n SleepDisabled 0\n"))
        XCTAssertFalse(try PowerSettings.sleepDisabled(from: "System-wide power settings:\n"))
    }

    func testUnknownOutputDoesNotSilentlyReportOff() {
        for output in ["", "permission denied", "System-wide power settings:\n SleepDisabled banana", "System-wide power settings:\n SleepDisabled 2"] {
            XCTAssertThrowsError(try PowerSettings.sleepDisabled(from: output))
        }
    }

    func testScriptStringEscapesQuotesAndBackslashes() {
        XCTAssertEqual(PowerSettings.appleScriptString("say \"hi\" \\ path"), "\"say \\\"hi\\\" \\\\ path\"")
    }

    func testRecoveryRecordSurvivesRelaunch() throws {
        let record = LidRecovery(originalDisabled: false)
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(LidRecovery.self, from: data), record)
    }
}
