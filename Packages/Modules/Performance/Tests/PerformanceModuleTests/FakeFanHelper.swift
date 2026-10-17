import FanHelperKit
import Foundation
import Synchronization
@testable import PerformanceModule

/// A registration that does what the test says and records what it was asked. It never touches the system's service manager.
final class FakeFanHelperRegistration: FanHelperRegistering {
    enum Call: Equatable { case register, unregister, openSystemSettings }

    /// What the system says now; setting it drops any script.
    var status: FanHelperRegistrationStatus {
        get {
            if !script.isEmpty { return script.count > 1 ? script.removeFirst() : script[0] }
            return current
        }
        set {
            current = newValue
            script = []
        }
    }
    private var current: FanHelperRegistrationStatus
    /// Answers for the next reads of `status`, one each, the last one repeating: macOS catching up after a call.
    var script: [FanHelperRegistrationStatus] = []
    /// What the status is once `register()` has run, whether or not it threw.
    var statusAfterRegister = FanHelperRegistrationStatus.enabled
    var registerError: (any Error)?
    var unregisterError: (any Error)?
    private(set) var calls: [Call] = []

    init(status: FanHelperRegistrationStatus = .notRegistered) {
        current = status
    }

    func register() throws {
        calls.append(.register)
        current = statusAfterRegister
        if let registerError { throw registerError }
    }

    func unregister() async throws {
        calls.append(.unregister)
        if let unregisterError { throw unregisterError }
        current = .notRegistered
    }

    func openSystemSettings() { calls.append(.openSystemSettings) }
}

/// A helper that answers what the test queued; the last answer repeats.
nonisolated final class FakeFanHelperClient: FanHelperClient, Sendable {
    struct State {
        var pings: [Result<FanHelperInfo, FanHelperError>]
        var fans: Result<[FanHelperFanInfo], FanHelperError> = .success([])
        var pingCount = 0
        var readCount = 0
    }

    private let state: Mutex<State>

    init(pings: [Result<FanHelperInfo, FanHelperError>] = [.success(FanHelperInfo.matching)]) {
        state = Mutex(State(pings: pings))
    }

    var pingCount: Int { state.withLock { $0.pingCount } }
    var readCount: Int { state.withLock { $0.readCount } }

    func answerFans(_ fans: Result<[FanHelperFanInfo], FanHelperError>) { state.withLock { $0.fans = fans } }

    func ping() async throws -> FanHelperInfo {
        let result = state.withLock { state -> Result<FanHelperInfo, FanHelperError> in
            state.pingCount += 1
            return state.pings.count > 1 ? state.pings.removeFirst() : state.pings[0]
        }
        return try result.get()
    }

    func readFans() async throws -> [FanHelperFanInfo] {
        try state.withLock { state -> Result<[FanHelperFanInfo], FanHelperError> in
            state.readCount += 1
            return state.fans
        }.get()
    }
}

nonisolated extension FanHelperInfo {
    /// The helper that is in `BundledFanHelper.matching`.
    static let matching = FanHelperInfo(version: "1", buildID: "aaaa", euid: 0, pid: 321)
    static let oldBuild = FanHelperInfo(version: "1", buildID: "bbbb", euid: 0, pid: 322)
}

nonisolated extension BundledFanHelper {
    static let matching = BundledFanHelper(version: "1", buildID: "aaaa")
}

nonisolated extension FanHelperFanInfo {
    static let both = [
        FanHelperFanInfo(index: 0, rpm: 5173.4, minRPM: 1200, maxRPM: 5779, mode: 0, target: 5180),
        FanHelperFanInfo(index: 1, rpm: 5635.6, minRPM: 1200, maxRPM: 6241, mode: 0, target: 5640),
    ]
}

/// What a test of the manager holds on to.
struct HelperRig {
    let manager: FanHelperManager
    let registration: FakeFanHelperRegistration
    let client: FakeFanHelperClient
    let pauses: PauseLog

    final class PauseLog {
        var durations: [Duration] = []
    }

    @MainActor init(
        status: FanHelperRegistrationStatus = .notRegistered, bundled: BundledFanHelper = .matching,
        pings: [Result<FanHelperInfo, FanHelperError>] = [.success(.matching)], runningApps: Set<String> = []
    ) {
        let registration = FakeFanHelperRegistration(status: status)
        let client = FakeFanHelperClient(pings: pings)
        let pauses = PauseLog()
        self.registration = registration
        self.client = client
        self.pauses = pauses
        manager = FanHelperManager(
            registration: registration, client: client, bundled: { bundled }, runningApps: { runningApps },
            pause: { pauses.durations.append($0) }
        )
    }
}
