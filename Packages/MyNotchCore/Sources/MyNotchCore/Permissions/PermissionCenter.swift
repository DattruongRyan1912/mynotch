import Observation

/// Checks and requests system permissions, and opens System Settings.
public protocol PermissionCenter: AnyObject {
    /// Never prompts, so it is safe to call while rendering or polling.
    func status(of permission: Permission) -> PermissionStatus
    /// Prompts when the system still allows it, then returns the resulting status.
    func request(_ permission: Permission) async -> PermissionStatus
    func openSystemSettings(for permission: Permission)
}

/// Where "Cấp lần lượt" is: each missing permission in turn, one at a time.
nonisolated public enum PermissionWalkthrough: Equatable, Sendable {
    nonisolated public struct Step: Equatable, Sendable {
        public let permission: Permission
        /// 1-based, out of `total`.
        public let position: Int
        public let total: Int
    }

    case idle
    /// The request is running, usually a system prompt the user has to answer.
    case requesting(Step)
    /// Asked, but still not granted (System Settings is open, or the prompt was refused). Moves on once the permission
    /// is granted, or when skipped or stopped.
    case waiting(Step)

    public var step: Step? {
        switch self {
        case .idle: nil
        case .requesting(let step), .waiting(let step): step
        }
    }
}

/// What the enabled modules need and how much of it is granted: the data behind the Permissions page and the
/// status-bar nudge. TCC posts no notification when a permission changes, so statuses are re-read on demand
/// (`refresh()`) and every 2 s while the page is on screen.
@Observable
public final class PermissionOverview {
    @ObservationIgnored private let registry: ModuleRegistry
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var poll: ScheduledAction?
    @ObservationIgnored private var isPageVisible = false
    @ObservationIgnored private var isWindowVisible = true
    @ObservationIgnored private var walkQueue: [Permission] = []
    @ObservationIgnored private var walkTotal = 0
    /// Changes whenever a walkthrough ends, so a prompt answered late never moves a newer walkthrough along.
    @ObservationIgnored private var walkGeneration = 0
    /// A step is queued or running, so a second trigger must not start another one.
    @ObservationIgnored private var isAdvancing = false
    @ObservationIgnored private var walkTask: Task<Void, Never>?
    @ObservationIgnored private var launchPromptShown = false

    /// Of every permission a module declares, enabled or not, so switching a module on needs no refresh.
    public private(set) var statuses: [Permission: PermissionStatus] = [:]
    /// Permissions being requested now, so a second tap does not start a second request.
    public private(set) var granting: Set<Permission> = []
    public private(set) var walkthrough: PermissionWalkthrough = .idle

    /// Statuses and requests both go through the registry's permission center, so they can never disagree.
    public init(registry: ModuleRegistry, scheduler: any Scheduler, pollInterval: Duration = .seconds(2)) {
        self.registry = registry
        self.scheduler = scheduler
        self.pollInterval = pollInterval
        refresh()
    }

    // MARK: what is needed

    /// What the enabled modules need, required first.
    public var requirements: [PermissionRequirement] {
        PermissionRequirement.aggregate(registry.modules.map(\.descriptor).filter { registry.isEnabled($0.id) })
    }

    public var requiredRows: [PermissionRequirement] { requirements.filter(\.isRequired) }
    public var optionalRows: [PermissionRequirement] { requirements.filter { !$0.isRequired } }

    /// `.unknown` for a permission no module declares, which nothing asks about.
    public func status(of permission: Permission) -> PermissionStatus { statuses[permission] ?? .unknown }

    /// Required permissions of enabled modules that are denied or never asked; `unknown` ones cannot be told, so they do not count.
    public var missingRequiredCount: Int { requiredRows.count { status(of: $0.permission).isMissing } }

    /// The same for required and optional ones: what "Cấp lần lượt" walks through.
    public var missingCount: Int { requirements.count { status(of: $0.permission).isMissing } }

    /// Optional permissions of enabled modules that are denied or never asked. `PermissionRefreshLoop` keeps them current
    /// while someone is looking, since no module waits on an optional permission and nothing else polls for it.
    public var missingOptionalCount: Int { optionalRows.count { status(of: $0.permission).isMissing } }

    /// The status-bar menu entry, nil when nothing required is missing.
    public var nudgeTitle: String? {
        let count = missingRequiredCount
        return count > 0 ? "Thiếu \(count) quyền…" : nil
    }

    // MARK: refreshing

    /// Reads every status again. Call when the app becomes active and when the Settings window gains focus.
    public func refresh() {
        let declared = Set(registry.modules.flatMap { $0.descriptor.permissions + $0.descriptor.optionalPermissions })
        let fresh = Dictionary(uniqueKeysWithValues: declared.map { ($0, registry.permissionStatus(of: $0)) })
        if fresh != statuses { statuses = fresh }
        if case .waiting(let step) = walkthrough, !status(of: step.permission).isMissing { continueWalkthrough() }
    }

    /// Whether the Permissions page is the one showing. It polls only while the page and the window are both visible.
    public func setPageVisible(_ visible: Bool) {
        isPageVisible = visible
        updatePolling()
    }

    /// Whether the Settings window is on screen (not closed, minimized or covered).
    public func setWindowVisible(_ visible: Bool) {
        isWindowVisible = visible
        updatePolling()
    }

    private func updatePolling() {
        guard isPageVisible, isWindowVisible else {
            poll?.cancel()
            poll = nil
            return
        }
        guard poll == nil else { return }
        refresh()
        schedulePoll()
    }

    private func schedulePoll() {
        poll = scheduler.schedule(after: pollInterval) { [weak self] in
            guard let self else { return }
            refresh()
            schedulePoll()
        }
    }

    // MARK: granting

    /// Requests or opens System Settings (see `ModuleRegistry.grant`), then re-reads the statuses.
    public func grant(_ permission: Permission) async {
        guard granting.insert(permission).inserted else { return }
        defer { granting.remove(permission) }
        await registry.grant(permission)
        refresh()
    }

    // MARK: "Cấp lần lượt"

    /// Walks through every permission that is missing now, required ones first: request it, wait until the user has
    /// granted it (or skips it), then the next.
    public func startWalkthrough() {
        guard walkthrough == .idle, !isAdvancing else { return }
        walkQueue = requirements.map(\.permission).filter { status(of: $0).isMissing }
        walkTotal = walkQueue.count
        guard walkTotal > 0 else { return }
        continueWalkthrough()
    }

    /// Gives up on the permission being waited for and moves on. Does nothing while a prompt is open.
    public func skipWalkthroughStep() {
        guard case .waiting = walkthrough else { return }
        continueWalkthrough()
    }

    public func stopWalkthrough() {
        walkGeneration += 1
        walkQueue = []
        isAdvancing = false
        walkthrough = .idle
    }

    /// Returns once the walkthrough waits for the user or has ended.
    public func walkthroughSettled() async {
        await walkTask?.value
    }

    private func continueWalkthrough() {
        guard !isAdvancing else { return }
        isAdvancing = true
        let generation = walkGeneration
        walkTask = Task { await advanceWalkthrough(generation) }
    }

    private func advanceWalkthrough(_ generation: Int) async {
        defer { if generation == walkGeneration { isAdvancing = false } }
        while generation == walkGeneration, !walkQueue.isEmpty {
            let permission = walkQueue.removeFirst()
            guard status(of: permission).isMissing else { continue }
            let step = PermissionWalkthrough.Step(permission: permission, position: walkTotal - walkQueue.count, total: walkTotal)
            walkthrough = .requesting(step)
            await grant(permission)
            guard generation == walkGeneration else { return }
            if status(of: permission).isMissing {
                walkthrough = .waiting(step)
                return
            }
        }
        if generation == walkGeneration { walkthrough = .idle }
    }

    // MARK: opening the page by itself

    /// Whether Settings should open on its own now: on the first launch (no `previousIdentity`) or when the app's
    /// code-signing identity changed, which makes macOS forget what was granted, and only when something is missing.
    /// True at most once per launch. An identity that cannot be read counts as unchanged.
    public func shouldOpenAtLaunch(previousIdentity: String?, currentIdentity: String?) -> Bool {
        guard !launchPromptShown, missingCount > 0 else { return false }
        let isFirstLaunch = previousIdentity == nil
        let identityChanged = previousIdentity != nil && currentIdentity != nil && previousIdentity != currentIdentity
        guard isFirstLaunch || identityChanged else { return false }
        launchPromptShown = true
        return true
    }
}
