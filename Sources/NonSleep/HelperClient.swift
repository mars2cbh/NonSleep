import Foundation
import NonSleepCore

/// An error, a reply, and a timeout may race; exactly one resumes the awaiting task.
final class ReplyGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

enum HelperClient {
    static var bundledExecutable: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/NonSleepHelper")
    }

    static func ping() async throws {
        let version: Int = try await request { proxy, finish in
            proxy.ping { finish(.success($0)) }
        }
        guard version == HelperConfiguration.version else {
            throw AppError.message("전원 도우미 버전이 다릅니다. 설정에서 도우미를 다시 등록해 주세요.")
        }
    }

    static func setSleepDisabled(_ enabled: Bool) async throws {
        let _: Bool = try await request { proxy, finish in
            proxy.setSleepDisabled(enabled) { error in
                if let error { finish(.failure(AppError.message(error))) }
                else { finish(.success(true)) }
            }
        }
    }

    private static func request<Value>(_ invoke: (NonSleepHelperProtocol, @escaping (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        let connection = NSXPCConnection(machServiceName: HelperConfiguration.serviceName, options: .privileged)
        // Pin the helper as well as the client: an unrelated service cannot impersonate it.
        connection.setCodeSigningRequirement(try SigningIdentity.requirement(at: bundledExecutable))
        connection.remoteObjectInterface = NSXPCInterface(with: NonSleepHelperProtocol.self)
        defer {
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
            connection.invalidate()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate<Value>(continuation)
            let disconnected = AppError.message("전원 도우미에 연결하지 못했습니다. 설정에서 도우미 상태를 확인하거나 다시 등록해 주세요.")
            connection.invalidationHandler = { gate.finish(.failure(disconnected)) }
            connection.interruptionHandler = { gate.finish(.failure(disconnected)) }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                gate.finish(.failure(AppError.message("전원 도우미 통신 오류: \(error.localizedDescription)")))
            }) as? NonSleepHelperProtocol else {
                gate.finish(.failure(disconnected))
                return
            }
            invoke(proxy, gate.finish)
            DispatchQueue.global().asyncAfter(deadline: .now() + 12) {
                gate.finish(.failure(AppError.message("전원 도우미 응답 시간이 초과되었습니다. 설정에서 다시 확인해 주세요.")))
            }
        }
    }
}
