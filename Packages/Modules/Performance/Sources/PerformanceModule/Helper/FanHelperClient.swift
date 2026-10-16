import FanHelperKit
import Foundation
import Synchronization

/// Talks to the helper; faked in tests.
protocol FanHelperClient: Sendable {
    func ping() async throws -> FanHelperInfo
    func readFans() async throws -> [FanHelperFanInfo]
}

/// Waits for one answer from a call that can answer in three ways at once: a reply, an error handler and a timeout. The first
/// wins and the rest are ignored, because resuming a continuation twice crashes.
nonisolated enum XPCReply {
    static func run<T: Sendable>(
        timeout: Duration, _ start: @Sendable (@escaping @Sendable (Result<T, any Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            let timer = Task {
                try? await Task.sleep(for: timeout)
                once.resume(.failure(FanHelperError.timeout))
            }
            start { result in
                timer.cancel()
                once.resume(result)
            }
        }
    }

    /// Resumes its continuation the first time and never again.
    final class Once<T: Sendable>: Sendable {
        private let continuation: Mutex<CheckedContinuation<T, any Error>?>

        init(_ continuation: CheckedContinuation<T, any Error>) {
            self.continuation = Mutex(continuation)
        }

        func resume(_ result: Result<T, any Error>) {
            continuation.withLock { held in
                let taken = held
                held = nil
                return taken
            }?.resume(with: result)
        }
    }
}

/// The real client: a privileged connection to the helper's mach service, for one call, with the helper's signing requirement on
/// it (so a process that took the name without being the helper is not talked to). The connection is closed after the call: the
/// helper leaves by itself when nobody is connected.
final class XPCFanHelperClient: FanHelperClient {
    static let timeout = Duration.seconds(3)

    func ping() async throws -> FanHelperInfo {
        try await call { proxy, reply in
            proxy.ping { ping in
                reply(.success(FanHelperInfo(version: ping.version, buildID: ping.buildID, euid: ping.euid, pid: ping.pid)))
            }
        }
    }

    func readFans() async throws -> [FanHelperFanInfo] {
        try await call { proxy, reply in
            proxy.readFans { fans, failure in
                if let failure {
                    reply(.failure(FanHelperError.helperFailed(failure)))
                } else {
                    reply(.success(fans.map {
                        FanHelperFanInfo(index: $0.index, rpm: $0.rpm, minRPM: $0.minRPM, maxRPM: $0.maxRPM, mode: $0.mode, target: $0.target)
                    }))
                }
            }
        }
    }

    private func call<T: Sendable>(
        _ body: @Sendable (any FanHelperProtocol, @escaping @Sendable (Result<T, any Error>) -> Void) -> Void
    ) async throws -> T {
        nonisolated(unsafe) let connection = NSXPCConnection(machServiceName: FanHelperIdentity.machServiceName, options: .privileged)
        connection.remoteObjectInterface = FanHelperInterface.make()
        connection.setCodeSigningRequirement(FanHelperRequirement.helper)
        connection.resume()
        defer { connection.invalidate() }
        return try await XPCReply.run(timeout: Self.timeout) { reply in
            let proxy = connection.remoteObjectProxyWithErrorHandler { reply(.failure($0)) } as? any FanHelperProtocol
            guard let proxy else { return reply(.failure(FanHelperError.noProxy)) }
            body(proxy, reply)
        }
    }
}
