import FanHelperKit
import Foundation
import ServiceManagement

/// What the system says about the helper's registration, which is not the same as the helper running: `enabled` can be true while
/// no process answers.
nonisolated enum FanHelperRegistrationStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    /// Registered, but the user has not allowed it yet in System Settings, Login Items.
    case requiresApproval
    /// What macOS reports for a daemon that has never been registered (reports of developers say it often reads this instead of
    /// `notRegistered`, which it does on macOS 26.5 here), and for a bundle with no plist. The two cannot be told apart before
    /// registering, so it is treated as not installed: the install button is offered, and `register()` says what is wrong.
    case notFound

    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}

/// What a ping told: the helper that is running.
nonisolated struct FanHelperInfo: Equatable, Sendable {
    let version: String
    let buildID: String
    let euid: Int32
    let pid: Int32
}

/// One fan as the helper read it.
nonisolated struct FanHelperFanInfo: Equatable, Sendable {
    let index: Int
    let rpm: Double
    let minRPM: Double
    let maxRPM: Double
    /// -1 when the SMC did not have it.
    let mode: Double
    let target: Double
}

/// The helper that ships inside this app: the version this build of the app expects and the hash of the executable in the bundle
/// (nil when it cannot be read, say an unsigned debug build).
nonisolated struct BundledFanHelper: Equatable, Sendable {
    let version: String
    let buildID: String?

    static func current(bundleURL: URL = Bundle.main.bundleURL) -> BundledFanHelper {
        BundledFanHelper(
            version: FanHelperIdentity.version,
            buildID: CodeIdentity.buildID(ofFileAt: bundleURL.appending(path: FanHelperIdentity.helperProgram))
        )
    }
}

nonisolated enum FanHelperBusy: Equatable, Sendable {
    case installing
    case removing
    case updating
}

/// Where the helper is, for the tab and for Settings.
nonisolated enum FanHelperPhase: Equatable, Sendable {
    /// Not looked at yet.
    case unknown
    /// Nothing registered, which is also what macOS says (`.notFound`) about a daemon before its first `register()`; an error is
    /// shown only once a `register()` has thrown.
    case notInstalled
    case needsApproval
    case running(FanHelperInfo)
    /// Registered and enabled, but a ping got no answer.
    case unreachable(String)
    case failed(String)
    case busy(FanHelperBusy)
}

nonisolated enum FanHelperAction: Equatable, Sendable {
    case install
    case openSettings
    case retry
}

nonisolated enum FanHelperUpdateAction: Equatable, Sendable {
    case nothing
    case reRegister
}

/// When a helper that is already installed has to be registered again because the app was replaced under it.
nonisolated enum FanHelperUpdatePolicy {
    /// The running helper is not the one in the bundle: another version, or another build when both can be told.
    static func isOutdated(_ running: FanHelperInfo, bundled: BundledFanHelper) -> Bool {
        if running.version != bundled.version { return true }
        guard let bundledID = bundled.buildID, !running.buildID.isEmpty, running.buildID != "unknown" else { return false }
        return running.buildID != bundledID
    }

    /// Whether the running helper understands what this app sends it. That is the version's meaning, and only it: a build that differs
    /// within one version is replaced at the next launch but is not refused commands, so that the comparison of two hashes that
    /// could disagree for a real signed helper can never keep the probe or the curve from running.
    static func speaksTheProtocol(_ running: FanHelperInfo, bundled: BundledFanHelper) -> Bool {
        running.version == bundled.version
    }

    /// Only an enabled helper that answered is ever touched: one that is not registered was not asked for, one that waits for the
    /// user's approval is not running, and one that does not answer is reported, not retried in a loop. At most one attempt per
    /// launch of the app.
    static func decide(
        status: FanHelperRegistrationStatus, running: FanHelperInfo?, bundled: BundledFanHelper, alreadyTried: Bool
    ) -> FanHelperUpdateAction {
        guard status == .enabled, let running, !alreadyTried, isOutdated(running, bundled: bundled) else { return .nothing }
        return .reRegister
    }
}

nonisolated enum FanHelperError: Error, Equatable, Sendable {
    case timeout
    case noProxy
    case helperFailed(String)
}
