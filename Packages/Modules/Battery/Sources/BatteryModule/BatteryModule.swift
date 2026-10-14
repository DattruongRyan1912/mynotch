import MyNotchCore
import NotchUI
import Observation
import SwiftUI

@Observable
final class BatteryState {
    var snapshot: PowerSourceSnapshot?
    var details: BatteryDetails?
    var isLowPowerMode = false
    var lowThreshold = 20
    /// Whether the tab is on screen: the charging highlight and the polling only run then.
    var isTabVisible = false
}

/// What the tab tells the module about itself.
struct BatteryTabActions {
    var appeared: () -> Void
    var disappeared: () -> Void
}

/// Reference module: battery tab plus "charging" and "low battery" live activities.
public final class BatteryModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "battery",
        displayName: "Battery",
        systemImage: "battery.100percent.bolt",
        defaultEnabled: true,
        order: 900
    )

    let state = BatteryState()
    private let reader: any PowerSourceReading
    private var context: ModuleContext?
    private var lowActive = false
    /// Percent shown by the current low activity; re-published only when it changes, so frequent
    /// power-source callbacks don't keep re-raising it above other activities of the same priority.
    private var publishedLowPercent: Int?
    /// Threshold used for the previous decision, so lowering it in Settings dismisses the alert.
    private var lastThreshold: Int?
    private var pollTimer: ScheduledAction?
    /// Tabs on screen: each screen has its own notch, so more than one can show this tab at a time.
    private var visibleTabs = 0

    /// How often the open tab reads the battery again: the power flowing in or out changes without a notification.
    static let pollInterval = Duration.seconds(30)

    public init(reader: any PowerSourceReading = IOKitPowerSource()) {
        self.reader = reader
    }

    static let lowThresholdRange = 5...50

    /// Setting names and defaults in one place, shared by the running module and the Settings rows.
    static func keys(_ settings: ModuleSettings) -> (lowThreshold: SettingKey<Int>, notifyOnCharge: SettingKey<Bool>) {
        (settings.key("lowThreshold", default: 20, clampedTo: lowThresholdRange), settings.key("notifyOnCharge", default: true))
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        guard let snapshot = reader.read() else {
            throw .unavailable(reason: "Máy không có pin")
        }
        self.context = context
        lowActive = false
        publishedLowPercent = nil
        lastThreshold = nil
        apply(snapshot, previous: nil)
        readDetails()
        // The view reads `state`, so it is offered once and follows the percent by itself.
        context.lockScreen.set(AnyView(BatteryLockScreenView(state: state)), priority: .low)
        if !reader.startObserving({ [weak self] in self?.refresh() }) {
            context.logger.error("Power source notifications unavailable; battery data will not update")
        }
        let settings = context.settings
        let keys = Self.keys(settings)
        context.run { [weak self] in
            for await _ in Observations({ (settings.value(keys.lowThreshold), settings.value(keys.notifyOnCharge)) }) {
                self?.settingsChanged()
            }
        }
    }

    public func stop() async {
        reader.stopObserving()
        pollTimer?.cancel()
        pollTimer = nil
        context = nil
        state.snapshot = nil
        state.details = nil
        state.isLowPowerMode = false
        state.isTabVisible = false
        visibleTabs = 0
        lowActive = false
        publishedLowPercent = nil
        lastThreshold = nil
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Battery", systemImage: "battery.100percent", preferredHeight: BatteryTabView.preferredHeight,
            content: AnyView(BatteryTabView(state: state, actions: actions))
        )
    }

    var actions: BatteryTabActions {
        BatteryTabActions(appeared: { [weak self] in self?.tabAppeared() }, disappeared: { [weak self] in self?.tabDisappeared() })
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let keys = Self.keys(environment.settings)
        return AnyView(BatterySettingsView(
            lowThreshold: environment.settings.binding(keys.lowThreshold),
            lowThresholdRange: Self.lowThresholdRange,
            notifyOnCharge: environment.settings.binding(keys.notifyOnCharge)
        ))
    }

    func refresh() {
        guard let snapshot = reader.read() else { return }
        apply(snapshot, previous: state.snapshot)
        readDetails()
    }

    private func readDetails() {
        state.details = reader.readDetails()
        state.isLowPowerMode = reader.isLowPowerModeEnabled
    }

    /// Opening the tab shows fresh numbers, and from then on they are read again every `pollInterval`.
    private func tabAppeared() {
        guard context != nil else { return }
        visibleTabs += 1
        state.isTabVisible = true
        refresh()
        schedulePoll()
    }

    private func tabDisappeared() {
        visibleTabs = max(0, visibleTabs - 1)
        guard visibleTabs == 0 else { return }
        state.isTabVisible = false
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func schedulePoll() {
        pollTimer?.cancel()
        pollTimer = context?.scheduler.schedule(after: Self.pollInterval) { [weak self] in
            guard let self, state.isTabVisible else { return }
            refresh()
            schedulePoll()
        }
    }

    private func settingsChanged() {
        guard let snapshot = state.snapshot else { return }
        apply(snapshot, previous: snapshot)
    }

    private func apply(_ snapshot: PowerSourceSnapshot, previous: PowerSourceSnapshot?) {
        state.snapshot = snapshot
        guard let context else { return }
        let keys = Self.keys(context.settings)
        let threshold = context.settings.value(keys.lowThreshold)
        state.lowThreshold = threshold
        let policy = BatteryActivityPolicy(
            lowThreshold: threshold,
            notifyOnCharge: context.settings.value(keys.notifyOnCharge)
        )
        let decision = policy.decide(previous: previous, current: snapshot, lowActive: lowActive, previousThreshold: lastThreshold)
        lastThreshold = threshold
        if decision.showCharging {
            context.activities.set(LiveActivity(
                id: "charging", priority: .normal, expiresAfter: .seconds(4),
                leading: AnyView(BatteryActivityIcon(systemImage: "bolt.fill", tint: .green)),
                trailing: AnyView(BatteryActivityPercent(percent: snapshot.percent, tint: .green))
            ))
        } else if !snapshot.isOnAC {
            context.activities.clear(id: "charging")   // unplugged within the toast's lifetime
        }
        if decision.lowActive {
            if publishedLowPercent != snapshot.percent {
                context.activities.set(LiveActivity(
                    id: "low", priority: .high,
                    leading: AnyView(BatteryActivityIcon(systemImage: "battery.25percent", tint: .red)),
                    trailing: AnyView(BatteryActivityPercent(percent: snapshot.percent, tint: .red))
                ))
                publishedLowPercent = snapshot.percent
            }
        } else if lowActive {
            context.activities.clear(id: "low")
            publishedLowPercent = nil
        }
        lowActive = decision.lowActive
    }
}
