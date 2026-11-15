import Foundation
import os

private let limiterLog = Logger(subsystem: "io.lucasvu.mynotch", category: "battery.limiter")

/// Status of the privileged hardware helper daemon in ServiceManagement.
public enum SMCHelperStatus: String, Sendable, Equatable {
    case notInstalled
    case enabled
    case requiresApproval
    case notFound
}

/// Protocol for writing bytes to AppleSMC (e.g. via privileged helper or SMC client).
public protocol SMCChargeWriting: AnyObject, Sendable {
    func writeByte(key: String, value: UInt8) -> Bool
    func setChargeInhibit(inhibit: Bool) -> Bool
    func setChargeLimit(limit: Int) -> Bool
    func setDischarge(discharge: Bool) -> Bool
    var helperStatus: SMCHelperStatus { get }
    func registerHelper() throws
    func openSystemSettings()
    var onInhibitStateChanged: (@Sendable (Bool) -> Void)? { get set }
    var onDischargeStateChanged: (@Sendable (Bool) -> Void)? { get set }
}

public extension SMCChargeWriting {
    func setChargeInhibit(inhibit: Bool) -> Bool {
        writeByte(key: BatteryChargeLimiter.chargeInhibitKey, value: inhibit ? 1 : 0)
    }

    func setChargeLimit(limit: Int) -> Bool {
        writeByte(key: BatteryChargeLimiter.chargeLimitMaxKey, value: UInt8(clamping: limit))
    }

    func setDischarge(discharge: Bool) -> Bool {
        writeByte(key: BatteryChargeLimiter.chargeDischargeKey, value: discharge ? 0x08 : 0x00)
    }

    var helperStatus: SMCHelperStatus { .enabled }
    func registerHelper() throws {}
    func openSystemSettings() {}

    var onInhibitStateChanged: (@Sendable (Bool) -> Void)? {
        get { nil }
        set {}
    }

    var onDischargeStateChanged: (@Sendable (Bool) -> Void)? {
        get { nil }
        set {}
    }
}

/// Stages of the automated battery calibration cycle.
public enum BatteryCalibrationStage: String, Codable, Sendable, Equatable {
    case idle
    case topUp       // Step 1: Charge up to 100%
    case discharging // Step 2: Controlled forced discharge down to safety floor (15%)
    case recharging  // Step 3: Recharge back to user target limit
}

/// State of the battery charge limiter subsystem.
public struct BatteryChargeState: Equatable, Sendable {
    public var isLimitEnabled: Bool
    public var chargeLimit: Int
    public var isSailingEnabled: Bool
    public var sailingDelta: Int
    public var isAllowDischargeEnabled: Bool
    public var isDischargeActive: Bool
    public var isMagSafeLEDSyncEnabled: Bool
    public var isTopUpOnceActive: Bool
    public var isInhibited: Bool
    public var hardwareInhibitAvailable: Bool
    public var isBypassEnabled: Bool
    public var isGentleChargingEnabled: Bool
    public var isThermalThrottled: Bool
    public var calibrationStage: BatteryCalibrationStage
    public var calibrationTargetLimit: Int
    public var calibrationFloor: Int
    public var lastCalibrationTimestamp: Double
    public var calibrationIntervalDays: Int

    public init(
        isLimitEnabled: Bool = false,
        chargeLimit: Int = 80,
        isSailingEnabled: Bool = true,
        sailingDelta: Int = 20,
        isAllowDischargeEnabled: Bool = false,
        isDischargeActive: Bool = false,
        isMagSafeLEDSyncEnabled: Bool = true,
        isTopUpOnceActive: Bool = false,
        isInhibited: Bool = false,
        hardwareInhibitAvailable: Bool = false,
        isBypassEnabled: Bool = false,
        isGentleChargingEnabled: Bool = true,
        isThermalThrottled: Bool = false,
        calibrationStage: BatteryCalibrationStage = .idle,
        calibrationTargetLimit: Int = 80,
        calibrationFloor: Int = 15,
        lastCalibrationTimestamp: Double = 0.0,
        calibrationIntervalDays: Int = 0
    ) {
        self.isLimitEnabled = isLimitEnabled
        self.chargeLimit = chargeLimit
        self.isSailingEnabled = isSailingEnabled
        self.sailingDelta = sailingDelta
        self.isAllowDischargeEnabled = isAllowDischargeEnabled
        self.isDischargeActive = isDischargeActive
        self.isMagSafeLEDSyncEnabled = isMagSafeLEDSyncEnabled
        self.isTopUpOnceActive = isTopUpOnceActive
        self.isInhibited = isInhibited
        self.hardwareInhibitAvailable = hardwareInhibitAvailable
        self.isBypassEnabled = isBypassEnabled
        self.isGentleChargingEnabled = isGentleChargingEnabled
        self.isThermalThrottled = isThermalThrottled
        self.calibrationStage = calibrationStage
        self.calibrationTargetLimit = calibrationTargetLimit
        self.calibrationFloor = calibrationFloor
        self.lastCalibrationTimestamp = lastCalibrationTimestamp
        self.calibrationIntervalDays = calibrationIntervalDays
    }
}

/// Manages charge limiting, hardware SMC charge inhibit (CH0I/BCLM), direct power bypass mode,
/// gentle charging thermal throttling guard, sailing mode, controlled forced discharge (CHIE),
/// and automated calibration cycle (100% -> 15% -> Target Limit).
@MainActor
public final class BatteryChargeLimiter {
    public static let chargeInhibitKey = "CH0I"
    public static let chargeLimitMaxKey = "BCLM"
    public static let chargeDischargeKey = "CHIE"
    public static let magSafeLEDKey = "ACLC"

    public static let emergencySafetyFloorPercent: Int = 15 // Ngưỡng sàn khẩn cấp tối thượng
    public static let bypassSafetyFloorPercent: Int = 20    // Ngưỡng sàn an toàn của chế độ giới hạn / xả
    public static let defaultReassertionCooldownSeconds: TimeInterval = 15.0
    public var reassertionCooldownSeconds: TimeInterval = 15.0 // Cooldown chống spam XPC reassertion

    public static let thermalThrottleThresholdCelsius: Double = 34.0
    public static let thermalResumeThresholdCelsius: Double = 31.0

    public private(set) var state: BatteryChargeState
    public var onStateChanged: (@MainActor () -> Void)?
    public var smcWriterRef: (any SMCChargeWriting)? { smcWriter }
    private let smcWriter: (any SMCChargeWriting)?
    private var lastInhibitAssertionDate: Date = .distantPast
    private var lastDischargeAssertionDate: Date = .distantPast
    private var sailingHolding: Bool? = nil
    private var forceReassertOnNextEvaluation: Bool = false

    public init(
        isLimitEnabled: Bool = false,
        chargeLimit: Int = 80,
        isSailingEnabled: Bool = true,
        sailingDelta: Int = 20,
        isAllowDischargeEnabled: Bool = false,
        isMagSafeLEDSyncEnabled: Bool = true,
        isBypassEnabled: Bool = false,
        isGentleChargingEnabled: Bool = true,
        calibrationIntervalDays: Int = 0,
        lastCalibrationTimestamp: Double = 0.0,
        smcWriter: (any SMCChargeWriting)? = nil
    ) {
        self.smcWriter = smcWriter
        self.state = BatteryChargeState(
            isLimitEnabled: isLimitEnabled,
            chargeLimit: chargeLimit,
            isSailingEnabled: isSailingEnabled,
            sailingDelta: sailingDelta,
            isAllowDischargeEnabled: isAllowDischargeEnabled,
            isDischargeActive: false,
            isMagSafeLEDSyncEnabled: isMagSafeLEDSyncEnabled,
            isTopUpOnceActive: false,
            isInhibited: false,
            hardwareInhibitAvailable: smcWriter != nil,
            isBypassEnabled: isBypassEnabled,
            isGentleChargingEnabled: isGentleChargingEnabled,
            isThermalThrottled: false,
            calibrationStage: .idle,
            calibrationTargetLimit: chargeLimit,
            calibrationFloor: 15,
            lastCalibrationTimestamp: lastCalibrationTimestamp,
            calibrationIntervalDays: calibrationIntervalDays
        )

        smcWriter?.onInhibitStateChanged = { [weak self] isInhibited in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !isInhibited {
                    self.state.isInhibited = false
                    self.lastInhibitAssertionDate = .distantPast
                    self.onStateChanged?()
                }
            }
        }

        smcWriter?.onDischargeStateChanged = { [weak self] isDischarging in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !isDischarging {
                    self.state.isDischargeActive = false
                    self.lastDischargeAssertionDate = .distantPast
                    self.onStateChanged?()
                }
            }
        }
    }

    public func setLimitEnabled(_ enabled: Bool, snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        state.isLimitEnabled = enabled
        sailingHolding = nil
        if !enabled {
            state.isTopUpOnceActive = false
            emergencyCancelDischarge()
            applySMCLimit(100)
            let isIsolated = snapshot?.isAttachedToAdapter == true && snapshot?.isOnAC == false
            if state.isInhibited || isIsolated {
                applySMCInhibit(false)
                state.isInhibited = false
            }
        } else {
            applySMCLimit(state.chargeLimit)
        }
        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    public func setChargeLimit(_ limit: Int, snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        let clamped = max(50, min(100, limit))
        state.chargeLimit = clamped
        sailingHolding = nil
        if (state.isLimitEnabled || state.isBypassEnabled) && !state.isTopUpOnceActive && state.calibrationStage == .idle {
            applySMCLimit(clamped)
        }
        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    public func setSailingEnabled(_ enabled: Bool, delta: Int = 20, snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        state.isSailingEnabled = enabled
        state.sailingDelta = max(2, min(20, delta))
        sailingHolding = nil
        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    public func setAllowDischargeEnabled(_ enabled: Bool, snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        state.isAllowDischargeEnabled = enabled
        if !enabled && state.isDischargeActive && state.calibrationStage == .idle {
            emergencyCancelDischarge()
        }
        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    public func setMagSafeLEDSyncEnabled(_ enabled: Bool) {
        state.isMagSafeLEDSyncEnabled = enabled
    }

    public func setCalibrationIntervalDays(_ days: Int) {
        state.calibrationIntervalDays = max(0, days)
    }

    public func setBypassEnabled(_ enabled: Bool, snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        if enabled, let snap = snapshot, snap.percent <= Self.bypassSafetyFloorPercent {
            limiterLog.warning("setBypassEnabled(true) rejected: battery \(snap.percent)% <= \(Self.bypassSafetyFloorPercent)% safety floor")
            state.isBypassEnabled = false
            return
        }
        state.isBypassEnabled = enabled
        if enabled {
            forceReassertOnNextEvaluation = true
            lastInhibitAssertionDate = .distantPast
            let effectiveLimit = state.isLimitEnabled ? state.chargeLimit : (snapshot.map { min(state.chargeLimit, $0.percent) } ?? state.chargeLimit)
            applySMCLimit(effectiveLimit)
        } else {
            if !state.isLimitEnabled {
                applySMCLimit(100)
                if state.isInhibited {
                    applySMCInhibit(false)
                    state.isInhibited = false
                }
            } else {
                applySMCLimit(state.chargeLimit)
            }
        }
        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    public func setGentleChargingEnabled(_ enabled: Bool, snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        state.isGentleChargingEnabled = enabled
        if !enabled {
            state.isThermalThrottled = false
        }
        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    public func toggleTopUpOnce(snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        state.isTopUpOnceActive.toggle()
        if state.isTopUpOnceActive {
            emergencyCancelDischarge()
            applySMCLimit(100)
            applySMCInhibit(false)
            state.isInhibited = false
        } else {
            sailingHolding = nil
            if state.isLimitEnabled {
                applySMCLimit(state.chargeLimit)
            }
        }
        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    // MARK: - Calibration Cycle Lifecycle

    public func startCalibration(snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        // Must be attached to adapter to run calibration
        if let snap = snapshot, !snap.isAttachedToAdapter { return }
        
        state.calibrationTargetLimit = state.isLimitEnabled ? state.chargeLimit : 80
        state.isTopUpOnceActive = false

        if let snap = snapshot, snap.percent >= 100 {
            // Already at 100%, advance directly to Step 2: forced discharge down to 15%
            state.calibrationStage = .discharging
            if applySMCDischarge(true) {
                state.isDischargeActive = true
                lastDischargeAssertionDate = Date()
            } else {
                state.isDischargeActive = false
            }
            applySMCInhibit(false)
            state.isInhibited = false
        } else {
            // Step 1: Charge up to 100%
            state.calibrationStage = .topUp
            state.isDischargeActive = false
            applySMCDischarge(false)
            applySMCLimit(100)
            applySMCInhibit(false)
            state.isInhibited = false
        }

        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    public func cancelCalibration(snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        state.calibrationStage = .idle
        sailingHolding = nil
        if state.isDischargeActive {
            state.isDischargeActive = false
            applySMCDischarge(false)
        }
        lastDischargeAssertionDate = .distantPast
        if state.isLimitEnabled {
            applySMCLimit(state.chargeLimit)
        }
        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    public func emergencyCancelDischarge() {
        if state.calibrationStage == .discharging {
            state.calibrationStage = .idle
        }
        if state.isDischargeActive {
            state.isDischargeActive = false
            applySMCDischarge(false)
        }
        lastDischargeAssertionDate = .distantPast
    }

    /// Evaluates power-source snapshot and details, updating inhibit state, discharge state,
    /// calibration stage, and SMC registers.
    public func evaluate(snapshot: PowerSourceSnapshot, details: BatteryDetails? = nil) {
        limiterLog.info("evaluate: percent=\(snapshot.percent) isAttached=\(snapshot.isAttachedToAdapter) isOnAC=\(snapshot.isOnAC) isInhibited=\(self.state.isInhibited)")
        let isHardwareAdapterIsolated = snapshot.isAttachedToAdapter && !snapshot.isOnAC

        // Physically unplugged from adapter: cancel calibration and reset active discharge, top-up, thermal throttle, and inhibit states
        guard snapshot.isAttachedToAdapter else {
            limiterLog.warning("evaluate: adapter unplugged, resetting inhibit")
            sailingHolding = nil
            if state.calibrationStage != .idle {
                state.calibrationStage = .idle
            }
            if state.isDischargeActive {
                applySMCDischarge(false)
                state.isDischargeActive = false
            }
            lastDischargeAssertionDate = .distantPast
            if state.isInhibited {
                applySMCInhibit(false)
                state.isInhibited = false
            }
            state.isTopUpOnceActive = false
            state.isThermalThrottled = false
            return
        }

        // HARDWARE SAFETY FLOOR GUARD:
        // Bất cứ khi nào pin <= 20% (hoặc <= 15% khẩn cấp), BẮT BUỘC vô hiệu hoá ngay lập tức Inhibit / Discharge / Bypass!
        // Ngoại lệ duy nhất: Khi đang trong chu kỳ Calibration bước .discharging (xả xuống 15%) hoặc .recharging (nạp bù).
        if snapshot.percent <= Self.bypassSafetyFloorPercent {
            if state.calibrationStage == .discharging {
                if snapshot.percent <= state.calibrationFloor {
                    // Reached calibration floor (15%): transition to .recharging step
                    state.calibrationStage = .recharging
                    state.isDischargeActive = false
                    applySMCDischarge(false)
                    lastDischargeAssertionDate = .distantPast
                    applySMCLimit(state.calibrationTargetLimit)
                    applySMCInhibit(false)
                    state.isInhibited = false
                    return
                }
                // Still discharging down to calibration floor (15%), allow it to proceed
            } else if state.calibrationStage == .recharging {
                // Already in recharging recovery phase, allow charging to proceed back to target
            } else {
                limiterLog.fault("SAFETY FLOOR TRIGGERED! percent=\(snapshot.percent)% <= \(Self.bypassSafetyFloorPercent)%. Forcing AC charging!")
                applySMCInhibit(false)
                state.isInhibited = false
                if state.isDischargeActive {
                    applySMCDischarge(false)
                    state.isDischargeActive = false
                }
                lastDischargeAssertionDate = .distantPast
                if snapshot.percent <= Self.emergencySafetyFloorPercent {
                    state.isBypassEnabled = false
                    applySMCLimit(100)
                }
                if state.calibrationStage != .idle {
                    state.calibrationStage = .idle
                }
                state.isThermalThrottled = false
                return
            }
        }

        // Reached 100%: auto-reset one-time top-up
        if snapshot.percent >= 100 && state.calibrationStage == .idle {
            state.isTopUpOnceActive = false
        }

        // Hysteresis evaluation for Gentle Charging (Thermal Guard)
        if state.isGentleChargingEnabled, let temp = details?.temperatureCelsius {
            if temp >= Self.thermalThrottleThresholdCelsius {
                state.isThermalThrottled = true
                if state.isDischargeActive || state.calibrationStage == .discharging {
                    emergencyCancelDischarge()
                }
            } else if temp <= Self.thermalResumeThresholdCelsius {
                state.isThermalThrottled = false
            }
            // In range (31.0, 34.0): retain existing state.isThermalThrottled for stability
        } else if !state.isGentleChargingEnabled {
            state.isThermalThrottled = false
        }

        // Automated Calibration Cycle State Machine
        if state.calibrationStage != .idle {
            switch state.calibrationStage {
            case .topUp:
                if snapshot.percent >= 100 {
                    // Reached 100%: transition to Step 2 (discharging down to 15%)
                    state.calibrationStage = .discharging
                    if applySMCDischarge(true) {
                        state.isDischargeActive = true
                        lastDischargeAssertionDate = Date()
                    } else {
                        state.isDischargeActive = false
                    }
                    applySMCInhibit(false)
                    state.isInhibited = false
                    return
                } else {
                    let shouldInhibit = state.isThermalThrottled
                    if shouldInhibit != state.isInhibited {
                        state.isInhibited = shouldInhibit
                        applySMCInhibit(shouldInhibit)
                    }
                    if !state.isThermalThrottled {
                        applySMCLimit(100)
                    }
                    if state.isDischargeActive {
                        state.isDischargeActive = false
                        applySMCDischarge(false)
                    }
                    return
                }

            case .discharging:
                if snapshot.percent <= state.calibrationFloor {
                    // Reached safety floor (15%): transition to Step 3 (recharging to target limit)
                    state.calibrationStage = .recharging
                    state.isDischargeActive = false
                    applySMCDischarge(false)
                    lastDischargeAssertionDate = .distantPast
                    applySMCLimit(state.calibrationTargetLimit)
                    applySMCInhibit(false)
                    state.isInhibited = false
                    return
                } else {
                    let isHardwareStillOnAC = snapshot.isOnAC || snapshot.isCharging
                    let dischargeCooldownPassed = Date().timeIntervalSince(lastDischargeAssertionDate) >= reassertionCooldownSeconds
                    if !state.isDischargeActive || (isHardwareStillOnAC && dischargeCooldownPassed) {
                        if applySMCDischarge(true) {
                            state.isDischargeActive = true
                            lastDischargeAssertionDate = Date()
                        } else {
                            state.isDischargeActive = false
                        }
                    }
                    return
                }

            case .recharging:
                if snapshot.percent >= state.calibrationTargetLimit {
                    // Completed full calibration cycle!
                    state.calibrationStage = .idle
                    state.lastCalibrationTimestamp = Date().timeIntervalSince1970
                    // Fall through to regular limiter logic to inhibit at target limit
                } else {
                    let shouldInhibit = state.isThermalThrottled
                    if shouldInhibit != state.isInhibited {
                        state.isInhibited = shouldInhibit
                        applySMCInhibit(shouldInhibit)
                    }
                    if state.isDischargeActive {
                        state.isDischargeActive = false
                        applySMCDischarge(false)
                    }
                    return
                }

            case .idle:
                break
            }
        }

        let effectiveDelta = state.isSailingEnabled ? max(2, state.sailingDelta) : 3
        let targetUpper = state.isLimitEnabled ? state.chargeLimit : 100
        let targetLower = state.isLimitEnabled ? max(20, targetUpper - effectiveDelta) : targetUpper

        let now = Date()
        let cooldownPassed = now.timeIntervalSince(lastInhibitAssertionDate) >= reassertionCooldownSeconds
        let dischargeCooldownPassed = now.timeIntervalSince(lastDischargeAssertionDate) >= reassertionCooldownSeconds

        // Controlled forced discharge down to target
        if state.isLimitEnabled && state.isAllowDischargeEnabled && !state.isTopUpOnceActive && !state.isThermalThrottled && snapshot.percent > targetUpper {
            let isHardwareStillOnAC = snapshot.isOnAC || snapshot.isCharging
            let needsDischargeAssertion = !state.isDischargeActive || (isHardwareStillOnAC && dischargeCooldownPassed)
            if needsDischargeAssertion {
                if state.isInhibited {
                    state.isInhibited = false
                    applySMCInhibit(false)
                    lastInhibitAssertionDate = .distantPast
                }
                if applySMCDischarge(true) {
                    state.isDischargeActive = true
                    lastDischargeAssertionDate = now
                } else {
                    state.isDischargeActive = false
                }
            }
        } else {
            if state.isDischargeActive {
                state.isDischargeActive = false
                applySMCDischarge(false)
                lastDischargeAssertionDate = .distantPast
            }
        }

        // Sailing mode Hysteresis Phase Update (AlDente-style state machine)
        if state.isLimitEnabled {
            if snapshot.percent >= targetUpper || Self.rawPercentReached(details, target: targetUpper) {
                sailingHolding = true
            } else if snapshot.percent <= targetLower {
                sailingHolding = false
            } else if sailingHolding == nil {
                // Plugged in or limiter enabled within the sailing window (targetLower < percent < targetUpper):
                // Inhibit immediately to run on direct AC power without topping up.
                sailingHolding = true
            }
        } else {
            sailingHolding = nil
        }

        let shouldInhibit: Bool
        if state.isThermalThrottled {
            // Hardware safety first: always cancel any active discharge and inhibit charging
            if state.isDischargeActive {
                emergencyCancelDischarge()
            }
            shouldInhibit = true
        } else if state.isTopUpOnceActive {
            // User requested temporary 100% boost and cell temperature is safe
            shouldInhibit = false
        } else if state.isDischargeActive {
            // MUTUAL EXCLUSION: Khi đang xả pin, TUYỆT ĐỐI KHÔNG kích hoạt Inhibit/Passthrough
            shouldInhibit = false
        } else if state.isBypassEnabled {
            if snapshot.percent > Self.bypassSafetyFloorPercent {
                shouldInhibit = true
            } else {
                shouldInhibit = false
            }
        } else if state.isLimitEnabled {
            shouldInhibit = (sailingHolding == true)
        } else {
            shouldInhibit = false
        }

        let isHardwareStillCharging: Bool = {
            if let watts = details?.batteryWatts { return watts > 0.8 }
            if let ma = details?.amperageMilliamps { return ma > 100 }
            return snapshot.isCharging
        }()

        if shouldInhibit {
            let needsAssertion = !state.isInhibited || (isHardwareStillCharging && cooldownPassed) || forceReassertOnNextEvaluation
            if needsAssertion {
                if applySMCInhibit(true) {
                    forceReassertOnNextEvaluation = false
                    state.isInhibited = true
                    lastInhibitAssertionDate = now
                }
                if (state.isLimitEnabled || state.isBypassEnabled) && !state.isTopUpOnceActive && state.calibrationStage == .idle {
                    let effectiveLimit = state.isLimitEnabled ? state.chargeLimit : min(state.chargeLimit, snapshot.percent)
                    applySMCLimit(effectiveLimit)
                }
            }
        } else {
            let needsRelease = !state.isDischargeActive && (state.isInhibited || isHardwareAdapterIsolated)
            if needsRelease {
                if applySMCInhibit(false) {
                    state.isInhibited = false
                    lastInhibitAssertionDate = .distantPast
                }
            }
        }
    }

    /// Fast re-assertion of SMC charge inhibit immediately upon system wake.
    public func handleWake() {
        forceReassertOnNextEvaluation = true
        lastInhibitAssertionDate = .distantPast
        if state.isLimitEnabled && !state.isTopUpOnceActive && state.calibrationStage == .idle {
            _ = applySMCLimit(state.chargeLimit)
        }
    }

    /// Resyncs hardware registers when the helper daemon becomes available or is re-registered.
    public func resyncHardware(snapshot: PowerSourceSnapshot? = nil, details: BatteryDetails? = nil) {
        forceReassertOnNextEvaluation = true
        lastInhibitAssertionDate = .distantPast
        if state.isLimitEnabled && !state.isTopUpOnceActive && state.calibrationStage == .idle {
            _ = applySMCLimit(state.chargeLimit)
        }
        if state.isInhibited {
            _ = applySMCInhibit(true)
        }
        if let snapshot {
            evaluate(snapshot: snapshot, details: details)
        }
    }

    @discardableResult
    private func applySMCInhibit(_ inhibit: Bool) -> Bool {
        limiterLog.info("applySMCInhibit(\(inhibit)): current isInhibited=\(self.state.isInhibited)")
        guard let smcWriter else { return true }
        return smcWriter.setChargeInhibit(inhibit: inhibit)
    }

    @discardableResult
    private func applySMCLimit(_ limit: Int) -> Bool {
        guard let smcWriter else { return true }
        return smcWriter.setChargeLimit(limit: limit)
    }

    @discardableResult
    private func applySMCDischarge(_ discharge: Bool) -> Bool {
        guard let smcWriter else { return true }
        return smcWriter.setDischarge(discharge: discharge)
    }

    private static func rawPercentReached(_ d: BatteryDetails?, target: Int) -> Bool {
        guard let cur = d?.currentCapacityMah, let max = d?.maxCapacityMah else { return false }
        guard cur > 100, max > 100 else { return false }
        guard Double(cur) <= Double(max) * 1.05 else { return false }
        return Double(cur) * 100 / Double(max) >= Double(target)
    }

    /// Safely restores all hardware SMC registers to their factory defaults
    /// when the module is stopped or when the application is terminating.
    public func releaseHardwareOnTermination() {
        emergencyCancelDischarge()
        _ = applySMCDischarge(false)
        _ = applySMCInhibit(false)
        _ = applySMCLimit(100)
        state.isInhibited = false
        state.isDischargeActive = false
        state.calibrationStage = .idle
        sailingHolding = nil
        lastDischargeAssertionDate = .distantPast
        lastInhibitAssertionDate = .distantPast
    }
}
