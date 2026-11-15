import AppKit
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
    var isLimitToEightyEnabled = false
    var chargeLimit = 80
    var isSailingEnabled = true
    var sailingDelta = 20
    var isAllowDischargeEnabled = true
    var isDischargeActive = false
    var isMagSafeLEDSyncEnabled = true
    var isTopUpOnceActive = false
    var isBypassModeEnabled = false
    var isGentleChargingEnabled = true
    var isThermalThrottled = false
    var isInhibited = false
    var calibrationStage: BatteryCalibrationStage = .idle
    var calibrationIntervalDays: Int = 0
    var lastCalibrationTimestamp: Double = 0.0
    var lastSleepDrain: SleepDrainRecord? = nil
    var helperStatus: SMCHelperStatus = .enabled
    var isRegisteringHelper: Bool = false
    var helperNotice: String? = nil
    var chargeLimiter: BatteryChargeLimiter

    init(chargeLimiter: BatteryChargeLimiter = BatteryChargeLimiter()) {
        self.chargeLimiter = chargeLimiter
    }
}

/// What the tab tells the module about itself and user action callbacks.
struct BatteryTabActions {
    var appeared: () -> Void
    var disappeared: () -> Void
    var toggleLimitToEighty: () -> Void = {}
    var setChargeLimit: (Int) -> Void = { _ in }
    var toggleAllowDischarge: () -> Void = {}
    var toggleSailing: () -> Void = {}
    var toggleTopUpOnce: () -> Void = {}
    var toggleLowPowerMode: () -> Void = {}
    var toggleBypassMode: () -> Void = {}
    var toggleGentleCharging: () -> Void = {}
    var startCalibration: () -> Void = {}
    var cancelCalibration: () -> Void = {}
    var setCalibrationIntervalDays: (Int) -> Void = { _ in }
}

/// Reference module: battery tab plus "charging", "eighty-percent", and "low battery" live activities.
public final class BatteryModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "battery",
        displayName: "Battery",
        systemImage: "battery.100percent.bolt",
        defaultEnabled: true,
        order: 900
    )

    let state: BatteryState
    public let scheduleEngine: BatteryScheduleEngine
    public let historyStore: BatteryHistoryStore
    private let reader: any PowerSourceReading
    private let notificationPoster: any NativeNotificationPosting
    private var hasNotifiedEighty = false
    private var hasNotifiedHighTemp = false
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
    private var sleepGuard: BatterySleepGuard?
    private var terminationObserver: (any NSObjectProtocol)? = nil

    /// How often the open tab reads the battery again: the power flowing in or out changes without a notification.
    nonisolated static let pollInterval = Duration.seconds(30)
    /// How often background watchdog re-evaluates hardware registers on AC power when limiting is active.
    nonisolated static let guardPollInterval = Duration.seconds(10)
    /// Fast polling interval when approaching charge limit while charging to prevent overshoot.
    nonisolated static let fastGuardPollInterval = Duration.seconds(2)

    nonisolated static func guardInterval(
        snapshot: PowerSourceSnapshot?,
        details: BatteryDetails?,
        isLimitToEightyEnabled: Bool,
        isBypassModeEnabled: Bool = false,
        isTopUpOnceActive: Bool,
        calibrationStage: BatteryCalibrationStage,
        limiterState: BatteryChargeState
    ) -> Duration {
        if isBypassModeEnabled && limiterState.isBypassEnabled {
            let isHardwareCharging = snapshot?.isCharging == true || (details?.batteryWatts ?? 0) > 0.8
            if isHardwareCharging && !limiterState.isInhibited {
                return fastGuardPollInterval
            }
        }
        guard isLimitToEightyEnabled,
              calibrationStage == .idle,
              !isTopUpOnceActive else {
            return guardPollInterval
        }
        guard let percent = snapshot?.percent else { return guardPollInterval }

        // Adaptive fast polling when discharging back down to target limit
        if limiterState.isDischargeActive {
            if percent <= limiterState.chargeLimit + 2 {
                return fastGuardPollInterval
            }
            return guardPollInterval
        }

        guard !limiterState.isInhibited else {
            return guardPollInterval
        }
        let isHardwareCharging = snapshot?.isCharging == true || (details?.batteryWatts ?? 0) > 0.8
        guard isHardwareCharging else { return guardPollInterval }
        let fastRange = (limiterState.chargeLimit - 2)..<limiterState.chargeLimit
        if fastRange.contains(percent) {
            return fastGuardPollInterval
        }
        return guardPollInterval
    }

    private var guardInterval: Duration {
        Self.guardInterval(
            snapshot: state.snapshot,
            details: state.details,
            isLimitToEightyEnabled: state.isLimitToEightyEnabled,
            isBypassModeEnabled: state.isBypassModeEnabled,
            isTopUpOnceActive: state.isTopUpOnceActive,
            calibrationStage: state.calibrationStage,
            limiterState: state.chargeLimiter.state
        )
    }

    public init(
        reader: any PowerSourceReading = IOKitPowerSource(),
        smcWriter: (any SMCChargeWriting)? = nil,
        notificationPoster: any NativeNotificationPosting = SystemNativeNotificationCenter.shared,
        scheduleEngine: BatteryScheduleEngine = BatteryScheduleEngine(),
        historyStore: BatteryHistoryStore? = nil
    ) {
        self.reader = reader
        self.notificationPoster = notificationPoster
        self.scheduleEngine = scheduleEngine
        self.historyStore = historyStore ?? BatteryHistoryStore()
        let limiter = BatteryChargeLimiter(smcWriter: smcWriter)
        self.state = BatteryState(chargeLimiter: limiter)
        limiter.onStateChanged = { [weak self] in
            self?.updateChargeLimiterState()
        }
    }

    static let lowThresholdRange = 5...50

    /// Setting names and defaults in one place, shared by the running module and the Settings rows.
    static func keys(_ settings: ModuleSettings) -> (
        lowThreshold: SettingKey<Int>,
        notifyOnCharge: SettingKey<Bool>,
        notifyAtEighty: SettingKey<Bool>,
        limitToEighty: SettingKey<Bool>,
        chargeLimit: SettingKey<Int>,
        sailingMode: SettingKey<Bool>,
        sailingDelta: SettingKey<Int>,
        allowDischarge: SettingKey<Bool>,
        syncMagSafeLED: SettingKey<Bool>,
        sleepDrainAlert: SettingKey<Bool>,
        bypassMode: SettingKey<Bool>,
        gentleCharging: SettingKey<Bool>,
        calibrationIntervalDays: SettingKey<Int>,
        lastCalibrationTimestamp: SettingKey<Double>
    ) {
        (
            settings.key("lowThreshold", default: 20, clampedTo: lowThresholdRange),
            settings.key("notifyOnCharge", default: true),
            settings.key("notifyAtEighty", default: false),
            settings.key("limitToEighty", default: false),
            settings.key("chargeLimit", default: 80, clampedTo: 50...100),
            settings.key("sailingMode", default: true),
            settings.key("sailingDelta", default: 20, clampedTo: 2...20),
            settings.key("allowDischarge", default: true),
            settings.key("syncMagSafeLED", default: true),
            settings.key("sleepDrainAlert", default: true),
            settings.key("bypassMode", default: false),
            settings.key("gentleCharging", default: true),
            settings.key("calibrationIntervalDays", default: 0, clampedTo: 0...90),
            settings.key("lastCalibrationTimestamp", default: 0.0)
        )
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        guard let snapshot = reader.read() else {
            throw .unavailable(reason: "Máy không có pin")
        }
        self.context = context
        lowActive = false
        publishedLowPercent = nil
        lastThreshold = nil

        let settings = context.settings
        let keys = Self.keys(settings)

        state.isLimitToEightyEnabled = context.settings.value(keys.limitToEighty)
        state.chargeLimit = context.settings.value(keys.chargeLimit)
        state.isSailingEnabled = context.settings.value(keys.sailingMode)
        state.sailingDelta = context.settings.value(keys.sailingDelta)
        state.isAllowDischargeEnabled = context.settings.value(keys.allowDischarge)
        state.isMagSafeLEDSyncEnabled = context.settings.value(keys.syncMagSafeLED)
        state.isBypassModeEnabled = context.settings.value(keys.bypassMode)
        state.isGentleChargingEnabled = context.settings.value(keys.gentleCharging)
        state.calibrationIntervalDays = context.settings.value(keys.calibrationIntervalDays)
        state.lastCalibrationTimestamp = context.settings.value(keys.lastCalibrationTimestamp)

        state.chargeLimiter.setChargeLimit(state.chargeLimit, snapshot: snapshot, details: nil)
        state.chargeLimiter.setSailingEnabled(state.isSailingEnabled, delta: state.sailingDelta, snapshot: snapshot, details: nil)
        state.chargeLimiter.setAllowDischargeEnabled(state.isAllowDischargeEnabled, snapshot: snapshot, details: nil)
        state.chargeLimiter.setMagSafeLEDSyncEnabled(state.isMagSafeLEDSyncEnabled)
        state.chargeLimiter.setCalibrationIntervalDays(state.calibrationIntervalDays)
        state.chargeLimiter.setLimitEnabled(state.isLimitToEightyEnabled, snapshot: snapshot, details: nil)
        state.chargeLimiter.setBypassEnabled(state.isBypassModeEnabled, snapshot: snapshot, details: nil)
        state.chargeLimiter.setGentleChargingEnabled(state.isGentleChargingEnabled, snapshot: snapshot, details: nil)

        refreshHelperStatus()
        readDetails()
        historyStore.seedFromPmsetIfNeeded()
        apply(snapshot, previous: nil)
        // The view reads `state`, so it is offered once and follows the percent by itself.
        context.lockScreen.set(AnyView(BatteryLockScreenView(state: state)), priority: .low)
        if !reader.startObserving({ [weak self] in self?.refresh() }) {
            context.logger.error("Power source notifications unavailable; battery data will not update")
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state.chargeLimiter.releaseHardwareOnTermination()
            }
        }

        if context.settings.value(keys.sleepDrainAlert) {
            let guardInstance = BatterySleepGuard(
                readPercent: { [weak self] in self?.reader.read()?.percent },
                onDrainAlert: { [weak self] drain, _ in
                    guard let self, let context = self.context else { return }
                    context.activities.set(LiveActivity(
                        id: "sleep-drain", priority: .high, expiresAfter: .seconds(8),
                        leading: AnyView(BatteryActivityIcon(systemImage: "moon.stars.fill", tint: .yellow)),
                        trailing: AnyView(Text("Tụt \(drain)% khi ngủ").font(.caption).foregroundStyle(.secondary))
                    ))
                }
            )
            guardInstance.onWillSleep = { [weak self] in
                self?.state.chargeLimiter.cancelCalibration()
                self?.state.chargeLimiter.emergencyCancelDischarge()
            }
            guardInstance.onDidWake = { [weak self] in
                self?.state.chargeLimiter.handleWake()
                self?.refresh()
            }
            guardInstance.start()
            sleepGuard = guardInstance
        }
        context.run { [weak self] in
            for await _ in Observations({ (
                settings.value(keys.lowThreshold),
                settings.value(keys.notifyOnCharge),
                settings.value(keys.notifyAtEighty),
                settings.value(keys.limitToEighty),
                settings.value(keys.chargeLimit),
                settings.value(keys.sailingMode),
                settings.value(keys.sailingDelta),
                settings.value(keys.allowDischarge),
                settings.value(keys.syncMagSafeLED),
                settings.value(keys.bypassMode),
                settings.value(keys.gentleCharging),
                settings.value(keys.calibrationIntervalDays)
            ) }) {
                self?.settingsChanged()
            }
        }
    }

    public func stop() async {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        state.chargeLimiter.releaseHardwareOnTermination()
        reader.stopObserving()
        sleepGuard?.stop()
        sleepGuard = nil
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
        BatteryTabActions(
            appeared: { [weak self] in self?.tabAppeared() },
            disappeared: { [weak self] in self?.tabDisappeared() },
            toggleLimitToEighty: { [weak self] in self?.toggleLimitToEighty() },
            setChargeLimit: { [weak self] in self?.setChargeLimit($0) },
            toggleAllowDischarge: { [weak self] in self?.toggleAllowDischarge() },
            toggleSailing: { [weak self] in self?.toggleSailing() },
            toggleTopUpOnce: { [weak self] in self?.toggleTopUpOnce() },
            toggleLowPowerMode: { [weak self] in self?.toggleLowPowerMode() },
            toggleBypassMode: { [weak self] in self?.toggleBypassMode() },
            toggleGentleCharging: { [weak self] in self?.toggleGentleCharging() },
            startCalibration: { [weak self] in self?.startCalibration() },
            cancelCalibration: { [weak self] in self?.cancelCalibration() },
            setCalibrationIntervalDays: { [weak self] in self?.setCalibrationIntervalDays($0) }
        )
    }

    public var helperStatus: SMCHelperStatus {
        state.chargeLimiter.smcWriterRef?.helperStatus ?? .enabled
    }

    public func refreshHelperStatus() {
        let current = helperStatus
        let previous = state.helperStatus
        state.helperStatus = current
        if previous != .enabled && current == .enabled {
            state.chargeLimiter.resyncHardware(snapshot: state.snapshot, details: state.details)
            updateChargeLimiterState()
        }
    }

    public func registerHelper() {
        guard let writer = state.chargeLimiter.smcWriterRef else { return }
        state.isRegisteringHelper = true
        defer { state.isRegisteringHelper = false }
        do {
            try writer.registerHelper()
            refreshHelperStatus()
        } catch {
            refreshHelperStatus()
            state.helperNotice = "Vui lòng mở Cài đặt hệ thống > Mục đăng nhập để cho phép Helper."
        }
    }

    public func openSystemSettings() {
        state.chargeLimiter.smcWriterRef?.openSystemSettings()
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let keys = Self.keys(environment.settings)
        return AnyView(BatterySettingsView(
            lowThreshold: environment.settings.binding(keys.lowThreshold),
            lowThresholdRange: Self.lowThresholdRange,
            notifyOnCharge: environment.settings.binding(keys.notifyOnCharge),
            notifyAtEighty: environment.settings.binding(keys.notifyAtEighty),
            limitToEighty: environment.settings.binding(keys.limitToEighty),
            chargeLimit: environment.settings.binding(keys.chargeLimit),
            sailingMode: environment.settings.binding(keys.sailingMode),
            sailingDelta: environment.settings.binding(keys.sailingDelta),
            allowDischarge: environment.settings.binding(keys.allowDischarge),
            syncMagSafeLED: environment.settings.binding(keys.syncMagSafeLED),
            calibrationIntervalDays: environment.settings.binding(keys.calibrationIntervalDays),
            lastCalibrationTimestamp: state.lastCalibrationTimestamp,
            calibrationStage: state.calibrationStage,
            onStartCalibration: { [weak self] in self?.startCalibration() },
            onCancelCalibration: { [weak self] in self?.cancelCalibration() },
            sleepDrainAlert: environment.settings.binding(keys.sleepDrainAlert),
            bypassMode: environment.settings.binding(keys.bypassMode),
            gentleCharging: environment.settings.binding(keys.gentleCharging),
            helperStatus: state.helperStatus,
            onRegisterHelper: { [weak self] in self?.registerHelper() },
            onOpenSystemSettings: { [weak self] in self?.openSystemSettings() },
            onRefreshHelperStatus: { [weak self] in self?.refreshHelperStatus() }
        ))
    }

    func refresh() {
        if scheduleEngine.isEnabled {
            _ = scheduleEngine.applyActiveRule(at: Date(), to: self, force: false)
        }
        guard let snapshot = reader.read() else { return }
        readDetails()
        apply(snapshot, previous: state.snapshot)
    }

    private func readDetails() {
        state.details = reader.readDetails()
        state.isLowPowerMode = reader.isLowPowerModeEnabled
        if let sleepRecord = sleepGuard?.lastSleepRecord {
            state.lastSleepDrain = sleepRecord
        }
        evaluateDetailsNotifications(details: state.details)
    }

    private func evaluateDetailsNotifications(details: BatteryDetails?) {
        guard let temp = details?.temperatureCelsius else { return }
        let isOnAC = state.snapshot?.isOnAC == true || state.snapshot?.isAttachedToAdapter == true
        if temp >= 34.0, isOnAC {
            if !hasNotifiedHighTemp {
                hasNotifiedHighTemp = true
                Task { [notificationPoster] in
                    let payload = NativeNotificationPayload(
                        id: "battery.thermal.high",
                        title: "Cảnh báo nhiệt độ pin",
                        body: String(format: "Nhiệt độ cell pin vượt ngưỡng an toàn (%.1f°C ≥ 34°C). Hệ thống tạm ngắt sạc để bảo vệ pin.", temp),
                        sound: true
                    )
                    try? await notificationPoster.post(payload)
                }
            }
        } else if temp <= 31.0 {
            hasNotifiedHighTemp = false
        }
    }

    #if DEBUG
    public func updateDetailsForTest(_ details: BatteryDetails?) {
        state.details = details
        evaluateDetailsNotifications(details: details)
    }
    #endif

    public func toggleLimitToEighty() {
        guard let context else { return }
        let keys = Self.keys(context.settings)
        let current = context.settings.value(keys.limitToEighty)
        let next = !current
        context.settings.set(next, for: keys.limitToEighty)
        state.isLimitToEightyEnabled = next
        if next && (helperStatus == .notFound || helperStatus == .notInstalled) {
            registerHelper()
        }
        state.chargeLimiter.setLimitEnabled(next, snapshot: state.snapshot, details: state.details)
        updateChargeLimiterState()
    }

    public func setChargeLimit(_ limit: Int) {
        guard let context else { return }
        let keys = Self.keys(context.settings)
        let clamped = max(50, min(100, limit))
        context.settings.set(clamped, for: keys.chargeLimit)
        state.chargeLimit = clamped
        if clamped < 100 && !state.isLimitToEightyEnabled {
            context.settings.set(true, for: keys.limitToEighty)
            state.isLimitToEightyEnabled = true
            state.chargeLimiter.setLimitEnabled(true, snapshot: state.snapshot, details: state.details)
        } else if clamped == 100 && state.isLimitToEightyEnabled {
            context.settings.set(false, for: keys.limitToEighty)
            state.isLimitToEightyEnabled = false
            state.chargeLimiter.setLimitEnabled(false, snapshot: state.snapshot, details: state.details)
        }
        state.chargeLimiter.setChargeLimit(clamped, snapshot: state.snapshot, details: state.details)
        updateChargeLimiterState()
    }

    public func setAllowDischarge(_ enabled: Bool) {
        guard let context else { return }
        let keys = Self.keys(context.settings)
        context.settings.set(enabled, for: keys.allowDischarge)
        state.isAllowDischargeEnabled = enabled
        if enabled && !state.isLimitToEightyEnabled {
            context.settings.set(true, for: keys.limitToEighty)
            state.isLimitToEightyEnabled = true
            state.chargeLimiter.setLimitEnabled(true, snapshot: state.snapshot, details: state.details)
        }
        state.chargeLimiter.setAllowDischargeEnabled(enabled, snapshot: state.snapshot, details: state.details)
        updateChargeLimiterState()
    }

    public func toggleAllowDischarge() {
        guard let context else { return }
        let keys = Self.keys(context.settings)
        let current = context.settings.value(keys.allowDischarge)
        setAllowDischarge(!current)
    }

    public func setSailing(enabled: Bool, delta: Int? = nil) {
        guard let context else { return }
        let keys = Self.keys(context.settings)
        context.settings.set(enabled, for: keys.sailingMode)
        state.isSailingEnabled = enabled
        if let delta {
            let clampedDelta = max(2, min(20, delta))
            context.settings.set(clampedDelta, for: keys.sailingDelta)
            state.sailingDelta = clampedDelta
        }
        state.chargeLimiter.setSailingEnabled(enabled, delta: state.sailingDelta, snapshot: state.snapshot, details: state.details)
        updateChargeLimiterState()
    }

    public func toggleSailing() {
        guard let context else { return }
        let keys = Self.keys(context.settings)
        let current = context.settings.value(keys.sailingMode)
        setSailing(enabled: !current)
    }

    public func setScheduleEnabled(_ enabled: Bool) {
        scheduleEngine.setEnabled(enabled)
        if enabled {
            scheduleEngine.applyActiveRule(to: self, force: true)
        }
        schedulePoll()
    }

    public func toggleTopUpOnce() {
        state.chargeLimiter.toggleTopUpOnce(snapshot: state.snapshot, details: state.details)
        updateChargeLimiterState()
    }

    public func toggleBypassMode() {
        guard let context else { return }
        let keys = Self.keys(context.settings)
        let current = context.settings.value(keys.bypassMode)
        let next = !current
        context.settings.set(next, for: keys.bypassMode)
        state.isBypassModeEnabled = next
        if next && (helperStatus == .notFound || helperStatus == .notInstalled) {
            registerHelper()
        }
        state.chargeLimiter.setBypassEnabled(next, snapshot: state.snapshot, details: state.details)
        updateChargeLimiterState()
    }

    public func toggleGentleCharging() {
        guard let context else { return }
        let keys = Self.keys(context.settings)
        let current = context.settings.value(keys.gentleCharging)
        context.settings.set(!current, for: keys.gentleCharging)
        state.isGentleChargingEnabled = !current
        state.chargeLimiter.setGentleChargingEnabled(!current, snapshot: state.snapshot, details: state.details)
        updateChargeLimiterState()
    }

    public func startCalibration() {
        guard let context else { return }
        state.chargeLimiter.startCalibration(snapshot: state.snapshot, details: state.details)
        updateChargeLimiterState()
        context.activities.set(LiveActivity(
            id: "charge-guard", priority: .high, expiresAfter: .seconds(6),
            leading: AnyView(BatteryActivityIcon(systemImage: "arrow.triangle.2.circlepath", tint: .green)),
            trailing: AnyView(Text("Bắt đầu chu trình cân chỉnh pin (100% ➔ 15% ➔ Bù)").font(.caption).foregroundStyle(.secondary))
        ))
    }

    public func cancelCalibration() {
        guard let context else { return }
        state.chargeLimiter.cancelCalibration(snapshot: state.snapshot, details: state.details)
        updateChargeLimiterState()
        context.activities.set(LiveActivity(
            id: "charge-guard", priority: .normal, expiresAfter: .seconds(4),
            leading: AnyView(BatteryActivityIcon(systemImage: "xmark.circle.fill", tint: .secondary)),
            trailing: AnyView(Text("Đã hủy cân chỉnh pin").font(.caption).foregroundStyle(.secondary))
        ))
    }

    private func setCalibrationIntervalDays(_ days: Int) {
        guard let context else { return }
        let keys = Self.keys(context.settings)
        context.settings.set(days, for: keys.calibrationIntervalDays)
        state.calibrationIntervalDays = days
        state.chargeLimiter.setCalibrationIntervalDays(days)
    }

    private func toggleLowPowerMode() {
        Task {
            let target = !state.isLowPowerMode
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            proc.arguments = ["-a", "lowpowermode", target ? "1" : "0"]
            try? proc.run()
            proc.waitUntilExit()
            await MainActor.run { [weak self] in
                self?.refresh()
            }
        }
    }

    private func updateChargeLimiterState() {
        let previousInhibited = state.isInhibited
        let previousDischarge = state.isDischargeActive
        let previousCalibration = state.calibrationStage
        let previousTimestamp = state.lastCalibrationTimestamp
        let previousBypass = state.isBypassModeEnabled

        state.isInhibited = state.chargeLimiter.state.isInhibited
        state.isTopUpOnceActive = state.chargeLimiter.state.isTopUpOnceActive
        state.isLimitToEightyEnabled = state.chargeLimiter.state.isLimitEnabled
        state.chargeLimit = state.chargeLimiter.state.chargeLimit
        state.isSailingEnabled = state.chargeLimiter.state.isSailingEnabled
        state.sailingDelta = state.chargeLimiter.state.sailingDelta
        state.isAllowDischargeEnabled = state.chargeLimiter.state.isAllowDischargeEnabled
        state.isDischargeActive = state.chargeLimiter.state.isDischargeActive
        state.isBypassModeEnabled = state.chargeLimiter.state.isBypassEnabled
        state.isGentleChargingEnabled = state.chargeLimiter.state.isGentleChargingEnabled
        state.isThermalThrottled = state.chargeLimiter.state.isThermalThrottled
        state.calibrationStage = state.chargeLimiter.state.calibrationStage
        state.lastCalibrationTimestamp = state.chargeLimiter.state.lastCalibrationTimestamp

        if previousBypass && !state.isBypassModeEnabled, let context {
            let keys = Self.keys(context.settings)
            context.settings.set(false, for: keys.bypassMode)
            context.activities.set(LiveActivity(
                id: "charge-guard-emergency", priority: .high, expiresAfter: .seconds(8),
                leading: AnyView(BatteryActivityIcon(systemImage: "exclamationmark.shield.fill", tint: .red)),
                trailing: AnyView(Text("Pin yếu (\(state.snapshot?.percent ?? 0)%) • Đã ngắt Bypass & kích hoạt sạc khẩn cấp!").font(.caption).foregroundStyle(.secondary))
            ))
        } else if state.lastCalibrationTimestamp > 0 && state.lastCalibrationTimestamp != previousTimestamp, let context {
            let keys = Self.keys(context.settings)
            context.settings.set(state.lastCalibrationTimestamp, for: keys.lastCalibrationTimestamp)
            context.activities.set(LiveActivity(
                id: "charge-guard", priority: .high, expiresAfter: .seconds(8),
                leading: AnyView(BatteryActivityIcon(systemImage: "checkmark.seal.fill", tint: .green)),
                trailing: AnyView(Text("Đã hoàn tất cân chỉnh pin! Giữ pin ở \(state.chargeLimit)%").font(.caption).foregroundStyle(.secondary))
            ))
        } else if state.calibrationStage == .discharging && previousCalibration != .discharging, let context {
            context.activities.set(LiveActivity(
                id: "charge-guard", priority: .high, expiresAfter: .seconds(6),
                leading: AnyView(BatteryActivityIcon(systemImage: "bolt.badge.arrow.down.fill", tint: .orange)),
                trailing: AnyView(Text("Cân pin: Đang xả xuống 15%").font(.caption).foregroundStyle(.secondary))
            ))
        } else if state.isDischargeActive, !previousDischarge, let context {
            context.activities.set(LiveActivity(
                id: "charge-guard", priority: .high, expiresAfter: .seconds(6),
                leading: AnyView(BatteryActivityIcon(systemImage: "bolt.badge.arrow.down.fill", tint: .orange)),
                trailing: AnyView(Text("Tự động xả về \(state.chargeLimit)%").font(.caption).foregroundStyle(.secondary))
            ))
        } else if state.isInhibited, !previousInhibited, let context, state.snapshot != nil {
            if state.isThermalThrottled {
                let tempStr = state.details?.temperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "nóng"
                context.activities.set(LiveActivity(
                    id: "charge-guard", priority: .high, expiresAfter: .seconds(6),
                    leading: AnyView(BatteryActivityIcon(systemImage: "thermometer.sun.fill", tint: .orange)),
                    trailing: AnyView(Text("Hạ nhiệt pin (\(tempStr)) • Tạm ngắt sạc").font(.caption).foregroundStyle(.secondary))
                ))
            } else if state.isBypassModeEnabled {
                let isDischarging = (state.details?.batteryWatts ?? 0) < -0.8 || (state.details?.amperageMilliamps ?? 0) < -100
                let bypassText = isDischarging
                    ? "Ngắt củ sạc • Đang dùng pin bảo vệ ngưỡng \(state.chargeLimit)%"
                    : "Nguồn trực tiếp • Nuôi máy không nạp pin"
                context.activities.set(LiveActivity(
                    id: "charge-guard", priority: .high, expiresAfter: .seconds(6),
                    leading: AnyView(BatteryActivityIcon(systemImage: "powerplug.fill", tint: isDischarging ? .orange : .green)),
                    trailing: AnyView(Text(bypassText).font(.caption).foregroundStyle(.secondary))
                ))
            } else {
                context.activities.set(LiveActivity(
                    id: "charge-guard", priority: .high, expiresAfter: .seconds(6),
                    leading: AnyView(BatteryActivityIcon(systemImage: "bolt.shield.fill", tint: .green)),
                    trailing: AnyView(Text("\(state.chargeLimit)% • Đang giữ sạc bảo vệ pin").font(.caption).foregroundStyle(.secondary))
                ))
            }
        }
        schedulePoll()
    }

    /// Opening the tab shows fresh numbers, and from then on they are read again every `pollInterval`.
    private var needsBackgroundGuard: Bool {
        if scheduleEngine.isEnabled { return true }
        guard state.snapshot?.isAttachedToAdapter == true else { return false }
        return state.isLimitToEightyEnabled
            || state.isBypassModeEnabled
            || state.calibrationStage != .idle
            || state.isThermalThrottled
    }

    private func tabAppeared() {
        guard context != nil else { return }
        visibleTabs += 1
        state.isTabVisible = true
        refresh()
        schedulePoll()
    }

    private func tabDisappeared() {
        visibleTabs = max(0, visibleTabs - 1)
        if visibleTabs == 0 {
            state.isTabVisible = false
        }
        schedulePoll()
    }

    private func schedulePoll() {
        pollTimer?.cancel()
        if needsBackgroundGuard {
            pollTimer = context?.scheduler.schedule(after: guardInterval) { [weak self] in
                guard let self else { return }
                refresh()
                schedulePoll()
            }
        } else if state.isTabVisible {
            pollTimer = context?.scheduler.schedule(after: Self.pollInterval) { [weak self] in
                guard let self, state.isTabVisible else { return }
                refresh()
                schedulePoll()
            }
        } else {
            pollTimer = nil
        }
    }

    private func settingsChanged() {
        guard let snapshot = state.snapshot, let context else { return }
        let keys = Self.keys(context.settings)
        let limitEnabled = context.settings.value(keys.limitToEighty)
        let limitVal = context.settings.value(keys.chargeLimit)
        let sailingEnabled = context.settings.value(keys.sailingMode)
        let sailingDeltaVal = context.settings.value(keys.sailingDelta)
        let allowDischargeVal = context.settings.value(keys.allowDischarge)
        let magSafeLEDVal = context.settings.value(keys.syncMagSafeLED)
        let bypassEnabled = context.settings.value(keys.bypassMode)
        let gentleEnabled = context.settings.value(keys.gentleCharging)
        let calibDays = context.settings.value(keys.calibrationIntervalDays)

        var changed = false
        if state.calibrationIntervalDays != calibDays {
            state.calibrationIntervalDays = calibDays
            state.chargeLimiter.setCalibrationIntervalDays(calibDays)
            changed = true
        }
        if state.chargeLimit != limitVal {
            state.chargeLimit = limitVal
            state.chargeLimiter.setChargeLimit(limitVal, snapshot: nil, details: state.details)
            changed = true
        }
        if state.isSailingEnabled != sailingEnabled || state.sailingDelta != sailingDeltaVal {
            state.isSailingEnabled = sailingEnabled
            state.sailingDelta = sailingDeltaVal
            state.chargeLimiter.setSailingEnabled(sailingEnabled, delta: sailingDeltaVal, snapshot: nil, details: state.details)
            changed = true
        }
        if state.isAllowDischargeEnabled != allowDischargeVal {
            state.isAllowDischargeEnabled = allowDischargeVal
            state.chargeLimiter.setAllowDischargeEnabled(allowDischargeVal, snapshot: nil, details: state.details)
            changed = true
        }
        if state.isMagSafeLEDSyncEnabled != magSafeLEDVal {
            state.isMagSafeLEDSyncEnabled = magSafeLEDVal
            state.chargeLimiter.setMagSafeLEDSyncEnabled(magSafeLEDVal)
            changed = true
        }
        if state.isLimitToEightyEnabled != limitEnabled {
            state.isLimitToEightyEnabled = limitEnabled
            if limitEnabled && (helperStatus == .notFound || helperStatus == .notInstalled) {
                registerHelper()
            }
            state.chargeLimiter.setLimitEnabled(limitEnabled, snapshot: nil, details: state.details)
            changed = true
        }
        if state.isBypassModeEnabled != bypassEnabled {
            state.isBypassModeEnabled = bypassEnabled
            state.chargeLimiter.setBypassEnabled(bypassEnabled, snapshot: nil, details: state.details)
            changed = true
        }
        if state.isGentleChargingEnabled != gentleEnabled {
            state.isGentleChargingEnabled = gentleEnabled
            state.chargeLimiter.setGentleChargingEnabled(gentleEnabled, snapshot: nil, details: state.details)
            changed = true
        }
        if changed {
            updateChargeLimiterState()
        }
        apply(snapshot, previous: snapshot)
    }

    private func apply(_ snapshot: PowerSourceSnapshot, previous: PowerSourceSnapshot?) {
        state.snapshot = snapshot
        state.chargeLimiter.evaluate(snapshot: snapshot, details: state.details)
        updateChargeLimiterState()

        let isOnAC = snapshot.isOnAC || snapshot.isAttachedToAdapter
        let mode: BatteryPowerMode
        if !isOnAC {
            mode = .discharging
        } else if snapshot.isCharging {
            mode = .charging
        } else {
            mode = .acPassthrough
        }
        let watts = state.details?.batteryWatts ?? 0.0
        historyStore.record(percent: snapshot.percent, mode: mode, watts: watts)

        if snapshot.percent >= 80, isOnAC {
            if !hasNotifiedEighty {
                hasNotifiedEighty = true
                Task { [notificationPoster] in
                    let payload = NativeNotificationPayload(
                        id: "battery.limit.eighty",
                        title: "Đã đạt ngưỡng sạc 80%",
                        body: "Pin đã đạt mức 80%, chuyển sang chế độ nuôi nguồn trực tiếp (Bypass) để bảo vệ cell pin.",
                        sound: true
                    )
                    try? await notificationPoster.post(payload)
                }
            }
        } else if snapshot.percent < 80 || !isOnAC {
            hasNotifiedEighty = false
        }

        evaluateDetailsNotifications(details: state.details)

        guard let context else { return }
        let keys = Self.keys(context.settings)
        let threshold = context.settings.value(keys.lowThreshold)
        state.lowThreshold = threshold
        let policy = BatteryActivityPolicy(
            lowThreshold: threshold,
            notifyOnCharge: context.settings.value(keys.notifyOnCharge),
            notifyAtEighty: context.settings.value(keys.notifyAtEighty)
        )
        let decision = policy.decide(previous: previous, current: snapshot, lowActive: lowActive, previousThreshold: lastThreshold)
        lastThreshold = threshold
        if decision.showCharging {
            context.activities.set(LiveActivity(
                id: "charging", priority: .normal, expiresAfter: .seconds(4),
                leading: AnyView(BatteryActivityIcon(systemImage: "bolt.fill", tint: .green)),
                trailing: AnyView(BatteryActivityPercent(percent: snapshot.percent, tint: .green))
            ))
        } else if !snapshot.isAttachedToAdapter {
            context.activities.clear(id: "charging")   // unplugged within the toast's lifetime
        }
        if decision.showEightyAlert {
            context.activities.set(LiveActivity(
                id: "eighty-percent", priority: .high, expiresAfter: .seconds(6),
                leading: AnyView(BatteryActivityIcon(systemImage: "battery.75percent", tint: .green)),
                trailing: AnyView(Text("80% • Rút sạc để bảo vệ pin").font(.caption).foregroundStyle(.secondary))
            ))
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
        schedulePoll()
    }
}

// MARK: - Battery Studio Telemetry Integration

public struct BatteryStudioStatus: Sendable {
    public let percent: Int
    public let isOnAC: Bool
    public let isCharging: Bool
    public let isLimitEnabled: Bool
    public var isLimitToEightyEnabled: Bool { isLimitEnabled }
    public let chargeLimit: Int
    public let isBypassEnabled: Bool
    public let isDischargeActive: Bool
    public let isAllowDischargeEnabled: Bool
    public let isSailingEnabled: Bool
    public let sailingDelta: Int
    public let isTopUpActive: Bool
    public let isHeatProtectionEnabled: Bool
    public let isHeatThrottled: Bool
    public let isCalibrationActive: Bool
    public let isScheduleEnabled: Bool
    public let activeScheduleRuleTitle: String?
    public let batteryWatts: Double?
    public let tempCelsius: Double?
    public let healthPercent: Int?
    public let cycleCount: Int?

    public init(
        percent: Int,
        isOnAC: Bool,
        isCharging: Bool,
        isLimitEnabled: Bool,
        chargeLimit: Int,
        isBypassEnabled: Bool,
        isDischargeActive: Bool,
        isAllowDischargeEnabled: Bool = false,
        isSailingEnabled: Bool,
        sailingDelta: Int = 5,
        isTopUpActive: Bool,
        isHeatProtectionEnabled: Bool = false,
        isHeatThrottled: Bool,
        isCalibrationActive: Bool,
        isScheduleEnabled: Bool = false,
        activeScheduleRuleTitle: String? = nil,
        batteryWatts: Double?,
        tempCelsius: Double?,
        healthPercent: Int?,
        cycleCount: Int?
    ) {
        self.percent = percent
        self.isOnAC = isOnAC
        self.isCharging = isCharging
        self.isLimitEnabled = isLimitEnabled
        self.chargeLimit = chargeLimit
        self.isBypassEnabled = isBypassEnabled
        self.isDischargeActive = isDischargeActive
        self.isAllowDischargeEnabled = isAllowDischargeEnabled
        self.isSailingEnabled = isSailingEnabled
        self.sailingDelta = sailingDelta
        self.isTopUpActive = isTopUpActive
        self.isHeatProtectionEnabled = isHeatProtectionEnabled
        self.isHeatThrottled = isHeatThrottled
        self.isCalibrationActive = isCalibrationActive
        self.isScheduleEnabled = isScheduleEnabled
        self.activeScheduleRuleTitle = activeScheduleRuleTitle
        self.batteryWatts = batteryWatts
        self.tempCelsius = tempCelsius
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
    }
}

extension BatteryModule {
    public func studioStatus() -> BatteryStudioStatus {
        let percent = state.snapshot?.percent ?? 0
        let isOnAC = state.snapshot?.isOnAC ?? false
        let isCharging = state.snapshot?.isCharging ?? false
        let activeRule = scheduleEngine.activeRule()
        return BatteryStudioStatus(
            percent: percent,
            isOnAC: isOnAC,
            isCharging: isCharging,
            isLimitEnabled: state.isLimitToEightyEnabled,
            chargeLimit: state.chargeLimit,
            isBypassEnabled: state.isBypassModeEnabled,
            isDischargeActive: state.isDischargeActive,
            isAllowDischargeEnabled: state.isAllowDischargeEnabled,
            isSailingEnabled: state.isSailingEnabled,
            sailingDelta: state.sailingDelta,
            isTopUpActive: state.isTopUpOnceActive,
            isHeatProtectionEnabled: state.isGentleChargingEnabled,
            isHeatThrottled: state.isThermalThrottled,
            isCalibrationActive: state.calibrationStage != .idle,
            isScheduleEnabled: scheduleEngine.isEnabled,
            activeScheduleRuleTitle: activeRule?.title,
            batteryWatts: state.details?.batteryWatts,
            tempCelsius: state.details?.temperatureCelsius,
            healthPercent: state.details?.healthPercent,
            cycleCount: state.details?.cycleCount
        )
    }
}
