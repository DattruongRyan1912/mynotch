import FanHelperKit
import Foundation
import Synchronization

/// Talks to the helper; faked in tests.
protocol FanHelperClient: Sendable {
    func ping() async throws -> FanHelperInfo
    func readFans() async throws -> [FanHelperFanInfo]
    /// Asks for at least `rpm` while Apple's control stays on. The helper holds it for a lease of 15 s.
    func setFloor(fan: Int, rpm: Double) async throws -> FanCommandResult
    /// Takes a fan to a manual speed (unless Apple's own is higher), or with `FanCommandResult.allFans` every fan to that speed, each
    /// held to its own range: the helper sets all the modes, then all the targets, and waits for the SMC to apply them. A lease of
    /// 15 s, renewed by sending it again.
    func setForced(fan: Int, rpm: Double) async throws -> FanCommandResult
    /// Gives one fan, or with `FanCommandResult.allFans` every fan, back to Apple.
    func setAuto(fan: Int) async throws -> FanCommandResult
}

/// What the helper answered to a command that sets a fan.
nonisolated struct FanCommandResult: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case automatic, floor, forced
    }

    static let allFans = FanHelperResult.allFans

    let ok: Bool
    let state: State
    /// What the helper wrote as the target; nil when it wrote none.
    let appliedRPM: Double?
    /// The helper's own short English line: why a request was clamped, refused or turned into automatic.
    let detail: String
    let leaseSeconds: Double
    /// How long the slowest mode this command wrote took to read back as written, in milliseconds; nil when it wrote none.
    let modeReadBackMS: Int?

    init(ok: Bool, state: State, appliedRPM: Double? = nil, detail: String = "", leaseSeconds: Double = 0, modeReadBackMS: Int? = nil) {
        self.ok = ok
        self.state = state
        self.appliedRPM = appliedRPM
        self.detail = detail
        self.leaseSeconds = leaseSeconds
        self.modeReadBackMS = modeReadBackMS
    }

    init(_ result: FanHelperResult) {
        let state: State = switch result.state {
        case .floor?: .floor
        case .forced?: .forced
        default: .automatic
        }
        self.init(
            ok: result.ok, state: state, appliedRPM: result.appliedRPM >= 0 ? result.appliedRPM : nil, detail: result.detail,
            leaseSeconds: result.leaseSeconds, modeReadBackMS: result.modeReadBackMS >= 0 ? result.modeReadBackMS : nil
        )
    }
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
    /// How long a call may wait for the helper. A helper that was not running is started by the first call: launchd takes its time
    /// (seconds, on a busy Mac) and the helper then spends about half a second finding its sensors before it listens, so the wait has
    /// to be long enough for a cold start. It was 3 s, which a cold start can exceed: the helper's log showed it serving a
    /// request after the app had given up on it.
    static let timeout = Duration.seconds(10)

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

    func setFloor(fan: Int, rpm: Double) async throws -> FanCommandResult {
        try await call { proxy, reply in proxy.setFloor(fan: fan, rpm: rpm) { reply(.success(FanCommandResult($0))) } }
    }

    func setForced(fan: Int, rpm: Double) async throws -> FanCommandResult {
        try await call { proxy, reply in proxy.setForced(fan: fan, rpm: rpm) { reply(.success(FanCommandResult($0))) } }
    }

    func setAuto(fan: Int) async throws -> FanCommandResult {
        try await call { proxy, reply in proxy.setAuto(fan: fan) { reply(.success(FanCommandResult($0))) } }
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
