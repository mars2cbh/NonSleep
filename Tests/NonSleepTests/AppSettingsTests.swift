import XCTest
import ServiceManagement
@testable import NonSleep

@MainActor
private final class FakeLoginService: LoginServiceManaging {
    var status: SMAppService.Status = .notRegistered
    var registrationError: Error?
    var unregistrationError: Error?
    var registrations = 0
    var unregistrations = 0
    func register() throws {
        registrations += 1
        if let registrationError { throw registrationError }
        status = .enabled
    }
    func unregister() async throws {
        unregistrations += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }
}

final class AppSettingsTests: XCTestCase {
    @MainActor
    func testLoginRegistrationAndRemovalUseActualServiceState() async {
        let service = FakeLoginService()
        let settings = AppSettings(loginService: service)
        await settings.setLoginEnabled(true)
        XCTAssertTrue(settings.loginEnabled)
        XCTAssertEqual(service.registrations, 1)
        await settings.setLoginEnabled(true)
        XCTAssertEqual(service.registrations, 1)
        await settings.setLoginEnabled(false)
        XCTAssertFalse(settings.loginEnabled)
        XCTAssertEqual(service.unregistrations, 1)
        XCTAssertFalse(settings.busy)
    }

    @MainActor
    func testRegistrationFailureDoesNotShowEnabled() async {
        let service = FakeLoginService()
        service.registrationError = AppError.message("Registration denied")
        let settings = AppSettings(loginService: service)
        await settings.setLoginEnabled(true)
        XCTAssertFalse(settings.loginEnabled)
        XCTAssertNotNil(settings.errorMessage)
        XCTAssertFalse(settings.busy)
    }

    @MainActor
    func testRemovalFailureDoesNotShowDisabled() async {
        let service = FakeLoginService()
        service.status = .enabled
        service.unregistrationError = AppError.message("Removal denied")
        let settings = AppSettings(loginService: service)
        await settings.setLoginEnabled(false)
        XCTAssertTrue(settings.loginEnabled)
        XCTAssertNotNil(settings.errorMessage)
        XCTAssertFalse(settings.busy)
    }

    @MainActor
    func testExternalRevocationIsReflectedOnRefresh() {
        let service = FakeLoginService()
        service.status = .enabled
        let settings = AppSettings(loginService: service)
        service.status = .requiresApproval
        settings.refreshLogin()
        XCTAssertFalse(settings.loginEnabled)
        XCTAssertEqual(settings.loginStatus, .requiresApproval)
        XCTAssertEqual(service.registrations, 0)
    }
}
