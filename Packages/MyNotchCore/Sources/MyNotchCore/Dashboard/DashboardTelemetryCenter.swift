import Foundation
import Observation

/// Aggregates live telemetry from modules for the Dashboard native window.
/// Polls only while `isWindowVisible` is true, ensuring zero CPU overhead when closed.
@Observable
@MainActor
public final class DashboardTelemetryCenter {
    public static let defaultPollInterval = Duration.seconds(2)

    public private(set) var isWindowVisible = false
    public private(set) var snapshots: [ModuleID: DashboardSnapshot] = [:]
    public private(set) var healthSummary = DashboardHealthSummary()
    public var selectedSection: DashboardSection = .overview
    public private(set) var lastRefreshDate: Date?

    @ObservationIgnored private let registry: ModuleRegistry
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var pollTimer: ScheduledAction?

    public init(
        registry: ModuleRegistry,
        scheduler: any Scheduler,
        pollInterval: Duration = defaultPollInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.registry = registry
        self.scheduler = scheduler
        self.pollInterval = pollInterval
        self.now = now
    }

    /// Sets whether the dashboard window is currently visible to the user.
    /// Starts periodic polling and notifies modules when becoming visible; stops polling when hidden.
    public func setWindowVisible(_ visible: Bool) {
        guard isWindowVisible != visible else { return }
        isWindowVisible = visible

        notifyModulesActive(visible)

        if visible {
            refresh()
            scheduleNextPoll()
        } else {
            stopPolling()
        }
    }

    /// Manually triggers a snapshot refresh across all registered modules.
    public func refresh() {
        lastRefreshDate = now()
        var newSnapshots: [ModuleID: DashboardSnapshot] = [:]

        for module in registry.modules {
            let id = module.descriptor.id
            if let reporter = module as? any DashboardReporting {
                newSnapshots[id] = reporter.dashboardSnapshot()
            } else {
                newSnapshots[id] = defaultSnapshot(for: module)
            }
        }

        snapshots = newSnapshots
        updateHealthSummary()
    }

    private func scheduleNextPoll() {
        pollTimer?.cancel()
        guard isWindowVisible else { return }
        pollTimer = scheduler.schedule(after: pollInterval) { [weak self] in
            guard let self, self.isWindowVisible else { return }
            self.refresh()
            self.scheduleNextPoll()
        }
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func notifyModulesActive(_ active: Bool) {
        for module in registry.modules {
            if let reporter = module as? any DashboardReporting {
                reporter.setDashboardActive(active)
            }
        }
    }

    private func defaultSnapshot(for module: any FeatureModule) -> DashboardSnapshot {
        let id = module.descriptor.id
        let isEnabled = registry.isEnabled(id)
        let state = registry.states[id] ?? .disabled
        let isRunning = state == .running

        let status: DashboardStatusLevel
        let summary: String

        if registry.isPaused && isEnabled {
            status = .warning
            summary = "Đang tạm dừng"
        } else if isRunning {
            status = .success
            summary = "Đang hoạt động"
        } else if !isEnabled {
            status = .normal
            summary = "Đã tắt"
        } else {
            status = .normal
            summary = "Chưa kích hoạt"
        }

        return DashboardSnapshot(
            moduleID: id,
            title: module.descriptor.displayName,
            systemImage: module.descriptor.systemImage,
            status: status,
            summary: summary,
            metrics: [
                DashboardMetric(name: "Trạng thái", value: .text(summary)),
            ],
            timestamp: now()
        )
    }

    private func updateHealthSummary() {
        let total = registry.modules.count
        var active = 0
        var disabled = 0
        var paused = 0

        for module in registry.modules {
            let id = module.descriptor.id
            let isEnabled = registry.isEnabled(id)
            let state = registry.states[id] ?? .disabled

            if registry.isPaused && isEnabled {
                paused += 1
            } else if state == .running {
                active += 1
            } else if !isEnabled {
                disabled += 1
            }
        }

        let hasWarnings = snapshots.values.contains { $0.status == .warning || $0.status == .critical }

        healthSummary = DashboardHealthSummary(
            totalModules: total,
            activeModules: active,
            pausedModules: paused,
            disabledModules: disabled,
            totalStorageBytes: registry.storageCenter.total,
            hasWarnings: hasWarnings
        )
    }
}

// MARK: - Module Snapshot Accessors

extension DashboardTelemetryCenter {
    public var performanceSnapshot: DashboardSnapshot? { snapshots["performance"] }
    public var batterySnapshot: DashboardSnapshot? { snapshots["battery"] }
    public var todoSnapshot: DashboardSnapshot? { snapshots["todo"] }
    public var habitSnapshot: DashboardSnapshot? { snapshots["habit"] }
    public var calendarSnapshot: DashboardSnapshot? { snapshots["calendar"] }
    public var mediaSnapshot: DashboardSnapshot? { snapshots["media"] }
    public var portsSnapshot: DashboardSnapshot? { snapshots["ports"] }
    public var cleanerSnapshot: DashboardSnapshot? { snapshots["cleaner"] }
    public var agentsSnapshot: DashboardSnapshot? { snapshots["aiagents"] }
    public var clipboardSnapshot: DashboardSnapshot? { snapshots["clipboard"] }
}
