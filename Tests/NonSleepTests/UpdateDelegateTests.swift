import XCTest
@testable import NonSleep

@MainActor
final class UpdateDelegateTests: XCTestCase {
    func testSparkleSecurityAndPermissionDelegatesAreConnected() {
        let updates = AppUpdates()
        XCTAssertTrue(updates.responds(to: NSSelectorFromString("updater:shouldProceedWithUpdate:updateCheck:error:")))
        XCTAssertTrue(updates.responds(to: NSSelectorFromString("updaterShouldPromptForPermissionToCheckForUpdates:")))
        XCTAssertTrue(updates.responds(to: NSSelectorFromString("feedURLStringForUpdater:")))
    }
}
