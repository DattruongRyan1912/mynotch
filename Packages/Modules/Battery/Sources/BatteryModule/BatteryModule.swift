import MyNotchCore
import NotchUI
import Observation
import SwiftUI

@Observable
final class BatteryState {
    var snapshot: PowerSourceSnapshot?
    var lowThreshold = 20
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
    private var settingKeys: (lowThreshold: SettingKey<Int>, notifyOnCharge: SettingKey<Bool>)?

    public init(reader: any PowerSourceReading = IOKitPowerSource()) {
        self.reader = reader
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        guard let snapshot = reader.read() else {
            throw .unavailable(reason: "Máy không có pin")
        }
        self.context = context
        settingKeys = (
            context.settings.key("lowThreshold", default: 20, clampedTo: 5...50),
            context.settings.key("notifyOnCharge", default: true)
        )
        lowActive = false
        publishedLowPercent = nil
        lastThreshold = nil
        apply(snapshot, previous: nil)
        reader.startObserving { [weak self] in self?.refresh() }
        if let keys = settingKeys {
            let settings = context.settings
            context.run { [weak self] in
                for await _ in Observations({ (settings.value(keys.lowThreshold), settings.value(keys.notifyOnCharge)) }) {
                    self?.settingsChanged()
                }
            }
        }
    }

    public func stop() async {
        reader.stopObserving()
        context = nil
        state.snapshot = nil
        lowActive = false
        publishedLowPercent = nil
        lastThreshold = nil
    }

    public func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: "Battery", systemImage: "battery.100percent", preferredHeight: 130, content: AnyView(BatteryTabView(state: state)))
    }

    public func makeSettingsView() -> AnyView? {
        guard let context, let keys = settingKeys else {
            return AnyView(Text("Bật module để chỉnh cài đặt").foregroundStyle(.secondary))
        }
        return AnyView(BatterySettingsView(
            lowThreshold: context.settings.binding(keys.lowThreshold),
            notifyOnCharge: context.settings.binding(keys.notifyOnCharge)
        ))
    }

    func refresh() {
        guard let snapshot = reader.read() else { return }
        apply(snapshot, previous: state.snapshot)
    }

    private func settingsChanged() {
        guard let snapshot = state.snapshot else { return }
        apply(snapshot, previous: snapshot)
    }

    private func apply(_ snapshot: PowerSourceSnapshot, previous: PowerSourceSnapshot?) {
        state.snapshot = snapshot
        guard let context, let keys = settingKeys else { return }
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
