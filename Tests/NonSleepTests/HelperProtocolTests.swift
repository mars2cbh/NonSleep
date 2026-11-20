import XCTest
import NonSleepCore
import Security
@testable import NonSleep

private final class FakePowerControl: NSObject, NonSleepHelperProtocol {
    private let lock = NSLock()
    private var requested: Bool?
    var lastRequest: Bool? {
        lock.lock(); defer { lock.unlock() }
        return requested
    }
    func ping(withReply reply: @escaping (Int) -> Void) { reply(HelperConfiguration.version) }
    func setSleepDisabled(_ enabled: Bool, withReply reply: @escaping (String?) -> Void) {
        lock.lock(); requested = enabled; lock.unlock()
        reply(nil)
    }
}

private final class LoopbackListener: NSObject, NSXPCListenerDelegate {
    let service = FakePowerControl()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Check message transport separately from identity validation below.
        // Production connections pin both peers on the privileged launchd service.
        connection.exportedInterface = NSXPCInterface(with: NonSleepHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

final class HelperProtocolTests: XCTestCase {
    func testLoopbackProtocolTransport() async throws {
        let delegate = LoopbackListener()
        let result = try await loopback(delegate)
        XCTAssertTrue(result)
        XCTAssertEqual(delegate.service.lastRequest, true)
    }

    func testDesignatedRequirementRejectsAnUnrelatedExecutable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = directory.appendingPathComponent("expected")
        let unrelated = directory.appendingPathComponent("unrelated")
        let source = Bundle(for: HelperProtocolTests.self).executableURL!
        for (destination, identifier) in [(expected, "dev.nonsleep.test.expected"), (unrelated, "dev.nonsleep.test.unrelated")] {
            try FileManager.default.copyItem(at: source, to: destination)
            _ = try await Commands.checked("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", identifier, destination.path])
        }
        let text = try SigningIdentity.requirement(at: expected)
        try SigningIdentity.validateRequirement(text)
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
        var expectedCode: SecStaticCode?
        var unrelatedCode: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(expected as CFURL, [], &expectedCode), errSecSuccess)
        XCTAssertEqual(SecStaticCodeCreateWithPath(unrelated as CFURL, [], &unrelatedCode), errSecSuccess)
        XCTAssertEqual(SecStaticCodeCheckValidity(expectedCode!, [], requirement), errSecSuccess)
        XCTAssertEqual(SecStaticCodeCheckValidity(unrelatedCode!, [], nil), errSecSuccess)
        XCTAssertNotEqual(SecStaticCodeCheckValidity(unrelatedCode!, [], requirement), errSecSuccess)
    }

    func testMalformedSigningRequirementsAreRejectedBeforeXPC() {
        XCTAssertThrowsError(try SigningIdentity.validateRequirement("this is not a signing requirement"))
    }

    func testInstallerShellQuotingKeepsPathsLiteral() async throws {
        let hostile = "/tmp/NonSleep's app; $(echo INJECTED) `echo INJECTED` \" 한글\nline"
        let command = "/usr/bin/printf '%s' " + PowerSettings.shellQuote(hostile)
        let output = try await Commands.checked("/bin/sh", ["-c", command])
        XCTAssertEqual(output, hostile)
    }

    private func loopback(_ delegate: LoopbackListener) async throws -> Bool {
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        let client = NSXPCConnection(listenerEndpoint: listener.endpoint)
        client.remoteObjectInterface = NSXPCInterface(with: NonSleepHelperProtocol.self)
        defer { client.invalidate(); listener.invalidate() }
        let result: Bool = try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate<Bool>(continuation)
            client.resume()
            let proxy = client.remoteObjectProxyWithErrorHandler { error in gate.finish(.failure(error)) } as! NonSleepHelperProtocol
            proxy.setSleepDisabled(true) { error in gate.finish(.success(error == nil)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                gate.finish(.failure(AppError.message("XPC loopback timed out")))
            }
        }
        withExtendedLifetime(delegate) {}
        return result
    }
}
