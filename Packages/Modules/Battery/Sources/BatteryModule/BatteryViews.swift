import NotchUI
import SwiftUI

/// The "Battery" tab: the battery gauge across the tab, an interactive charge control bar,
/// a dual-branch power flow pipeline with high-density Linear Telemetry, and a hardware security & thermal status footer.
struct BatteryTabView: View {
    static let gaugeHeight: CGFloat = BatteryGaugeLayout.height // 46
    static let controlsHeight: CGFloat = 26
    static let factsHeight: CGFloat = 68
    static let footerHeight: CGFloat = 14
    static let spacing: CGFloat = 8
    static let factsGap: CGFloat = spacing
    /// The tab bar's height when there are two or more tabs; `NotchTab.preferredHeight` includes it.
    static let tabBarHeight: CGFloat = 30
    /// Total declared height: content height (178 pt) + padding (28 pt) + tabBar (30 pt) = 236 pt.
    static let contentHeight = gaugeHeight + spacing + controlsHeight + spacing + factsHeight + spacing + footerHeight
    static let preferredHeight = contentHeight + NotchTokens.padding + tabBarHeight

    let state: BatteryState
    let actions: BatteryTabActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchIsOnScreen) private var isOnScreen

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear(perform: actions.appeared)
            .onDisappear(perform: actions.disappeared)
    }

    @ViewBuilder private var content: some View {
        if let snapshot = state.snapshot {
            let presentation = BatteryPresentation(
                snapshot: snapshot,
                details: state.details,
                isLowPowerMode: state.isLowPowerMode,
                lowThreshold: state.lowThreshold,
                isDischargeActive: state.isDischargeActive,
                targetLimit: state.isLimitToEightyEnabled ? state.chargeLimit : nil
            )
            VStack(alignment: .leading, spacing: Self.spacing) {
                BatteryGauge(
                    percent: snapshot.percent,
                    tone: presentation.tone,
                    isCharging: snapshot.isCharging,
                    isSweeping: BatteryGaugeMotion.isSweeping(
                        isCharging: snapshot.isCharging, isTabVisible: state.isTabVisible, isOnScreen: isOnScreen, reduceMotion: reduceMotion
                    ),
                    accessibilityLabel: presentation.accessibilityLabel,
                    limitMarkerPercent: state.isLimitToEightyEnabled ? state.chargeLimit : nil,
                    isLimitActive: state.isInhibited,
                    sailingDelta: (state.isLimitToEightyEnabled && state.isSailingEnabled) ? state.sailingDelta : nil,
                    showsPlug: BatteryGaugeMotion.showsPlug(
                        isCharging: snapshot.isCharging,
                        isAttachedToAdapter: snapshot.isAttachedToAdapter,
                        isDischargeActive: state.isDischargeActive
                    )
                )
                .frame(height: Self.gaugeHeight)

                BatteryControlBar(
                    state: state,
                    onToggleLimit: actions.toggleLimitToEighty,
                    onSetChargeLimit: actions.setChargeLimit,
                    onToggleAllowDischarge: actions.toggleAllowDischarge,
                    onToggleTopUp: actions.toggleTopUpOnce,
                    onToggleLowPower: actions.toggleLowPowerMode,
                    onToggleBypass: actions.toggleBypassMode,
                    onToggleGentle: actions.toggleGentleCharging,
                    onStartCalibration: actions.startCalibration,
                    onCancelCalibration: actions.cancelCalibration
                )
                .frame(height: Self.controlsHeight)

                if let flow = presentation.powerFlow {
                    VStack(spacing: 6) {
                        BatteryPowerFlowBar(flow: flow)
                            .frame(height: 31)
                        BatteryFactsRow(facts: presentation.technicalFacts)
                            .frame(height: 31)
                    }
                    .frame(height: Self.factsHeight, alignment: .top)
                } else {
                    BatteryFactsRow(facts: presentation.facts)
                        .frame(height: Self.factsHeight, alignment: .top)
                }

                BatteryFooterBar(state: state)
                    .frame(height: Self.footerHeight)
            }
        }
    }
}

/// Real-time dual-branch power flow pipeline:
/// Adapter IN ──┬──▶ Machine / System (CPU, GPU, Screen)
///              └──▶ Battery Pack (Cell charging or 0W Bypass)
struct BatteryPowerFlowBar: View {
    let flow: BatteryPowerFlow

    var body: some View {
        HStack(spacing: 0) {
            // Section 1: Power Adapter Input
            HStack(spacing: 5) {
                if !flow.isOnAC && flow.batteryWatts < -0.5 {
                    Image(systemName: "powerplug")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text("Tạm ngắt")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.orange)
                            .lineLimit(1)
                        Text("Củ sạc (Cô lập)")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(NotchTokens.secondaryText)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text(adapterWattsString)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(NotchTokens.primaryText)
                            .lineLimit(1)
                        Text("Củ sạc (Vào)")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(NotchTokens.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)

            // Flow Junction Connector
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 9.5, weight: .light))
                .foregroundStyle(NotchTokens.fill(0.35))
                .padding(.horizontal, 3)

            // Section 2: Machine / System Consumption (Logic Board, CPU, GPU, Display)
            HStack(spacing: 5) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(NotchTokens.secondaryText)
                VStack(alignment: .leading, spacing: 0.5) {
                    Text(String(format: "%.1f W", flow.systemWatts))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NotchTokens.primaryText)
                        .lineLimit(1)
                    Text("Nuôi máy")
                        .font(.system(size: 8.5, weight: .regular))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // Hairline separator
            Rectangle()
                .fill(NotchTokens.fill(0.12))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            // Section 3: Battery Pack Branch (Charging, Discharging, or Passthrough)
            HStack(spacing: 5) {
                if flow.batteryWatts > 0.5 {
                    Image(systemName: "battery.100percent.bolt")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text(String(format: "+%.1f W", flow.batteryWatts))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.green)
                            .lineLimit(1)
                        Text("Nạp vào pin")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(NotchTokens.secondaryText)
                            .lineLimit(1)
                    }
                } else if flow.batteryWatts < -0.5 {
                    Image(systemName: "bolt.badge.arrow.down.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text(String(format: "%.1f W", flow.batteryWatts))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.orange)
                            .lineLimit(1)
                        Text(flow.isDischargeActive ? "Tự động xả về \(flow.targetLimit ?? 80)%" : "Xả pin nuôi máy")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(NotchTokens.secondaryText)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "powerplug.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 0.5) {
                        Text("0.0 W (Passthrough)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.green)
                            .lineLimit(1)
                        Text("Ngắt nạp • Nuôi máy 100%")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(NotchTokens.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(NotchTokens.fill(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(NotchTokens.fill(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var adapterWattsString: String {
        if let actual = flow.adapterInputWatts {
            return String(format: "%.1f W", actual)
        }
        if let rated = flow.adapterWatts {
            return "\(rated) W"
        }
        return "Cắm sạc"
    }

    private var accessibilityLabel: String {
        if flow.isBypassActive {
            return "Nguồn vào: \(adapterWattsString). Nuôi máy: \(String(format: "%.1f", flow.systemWatts)) W. Nạp pin: 0 W (Bypass)"
        }
        return "Nguồn vào: \(adapterWattsString). Nuôi máy: \(String(format: "%.1f", flow.systemWatts)) W. Nạp pin: \(String(format: "%.1f", flow.batteryWatts)) W"
    }
}

/// Interactive control bar: Charge limit presets, direct power bypass mode, controlled discharge, gentle thermal charging,
/// calibration cycle, 100% boost top-up, and Low Power Mode quick toggle.
struct BatteryControlBar: View {
    let state: BatteryState
    let onToggleLimit: () -> Void
    let onSetChargeLimit: (Int) -> Void
    let onToggleAllowDischarge: () -> Void
    let onToggleTopUp: () -> Void
    let onToggleLowPower: () -> Void
    let onToggleBypass: () -> Void
    let onToggleGentle: () -> Void
    let onStartCalibration: () -> Void
    let onCancelCalibration: () -> Void

    private var isTrulyBypassing: Bool {
        guard let snapshot = state.snapshot, (snapshot.isOnAC || snapshot.isAttachedToAdapter) else { return false }
        let watts = state.details?.batteryWatts ?? 0
        let mA = state.details?.amperageMilliamps ?? 0
        if watts < -0.8 || mA < -100 { return false } // Đang xả pin -> Không phải passthrough
        if snapshot.isCharging {
            return watts <= 0.5
        }
        return abs(watts) <= 0.5
    }

    private var limitTitle: String {
        guard state.isLimitToEightyEnabled else { return "Giới hạn \(state.chargeLimit)%" }
        if state.isDischargeActive {
            return "Tự động xả về \(state.chargeLimit)%"
        }
        if isTrulyBypassing {
            return "Giữ \(state.chargeLimit)% (AC)"
        }
        if state.isInhibited && !isTrulyBypassing {
            return "Giữ \(state.chargeLimit)% (Sailing)"
        }
        if (state.snapshot?.percent ?? 0) < state.chargeLimit {
            return "Sạc tới \(state.chargeLimit)%"
        }
        return "Khóa \(state.chargeLimit)%"
    }

    private var calibrationIcon: String {
        switch state.calibrationStage {
        case .topUp: return "arrow.up.circle.fill"
        case .discharging: return "bolt.badge.arrow.down.fill"
        case .recharging: return "arrow.clockwise.circle.fill"
        case .idle: return "arrow.triangle.2.circlepath"
        }
    }

    private var calibrationTitle: String {
        switch state.calibrationStage {
        case .topUp: return "Cân pin: 1/3 (Sạc 100%)"
        case .discharging: return "Cân pin: 2/3 (Xả 15%)"
        case .recharging: return "Cân pin: 3/3 (Bù \(state.chargeLimit)%)"
        case .idle: return ""
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            // Calibration Active Pill (takes precedence when running)
            if state.calibrationStage != .idle {
                HStack(spacing: 3.5) {
                    Image(systemName: calibrationIcon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(calibrationTitle)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    Button(action: onCancelCalibration) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(NotchTokens.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(state.calibrationStage == .discharging ? Color.orange : Color.green)
                .padding(.horizontal, 6)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(NotchTokens.fill(state.calibrationStage == .discharging ? 0.16 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(NotchTokens.fill(state.calibrationStage == .discharging ? 0.35 : 0.22), lineWidth: 1)
                )
            } else {
                // Flexible Charge Limit Pill (AlDente style with presets menu)
                Button(action: onToggleLimit) {
                    HStack(spacing: 3.5) {
                        Image(systemName: state.isLimitToEightyEnabled ? "bolt.shield.fill" : "bolt.shield")
                            .font(.system(size: 10, weight: .semibold))
                        Text(limitTitle)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        if state.isLimitToEightyEnabled {
                            Circle()
                                .fill(state.isDischargeActive ? Color.orange : (isTrulyBypassing ? Color.green : (state.isInhibited ? Color.orange : Color.green)))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .foregroundStyle(state.isLimitToEightyEnabled ? NotchTokens.primaryText : NotchTokens.secondaryText)
                    .padding(.horizontal, 6)
                    .frame(maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(NotchTokens.fill(state.isLimitToEightyEnabled ? 0.12 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(NotchTokens.fill(state.isLimitToEightyEnabled ? 0.22 : 0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Text("Chọn mức giới hạn sạc")
                    Button("70%") { onSetChargeLimit(70) }
                    Button("75%") { onSetChargeLimit(75) }
                    Button("80% (Khuyến nghị)") { onSetChargeLimit(80) }
                    Button("85%") { onSetChargeLimit(85) }
                    Button("90%") { onSetChargeLimit(90) }
                    Divider()
                    if state.calibrationStage == .idle {
                        Button("Bắt đầu cân chỉnh pin (100% ➔ 15% ➔ Bù)...") { onStartCalibration() }
                    } else {
                        Button("Hủy chu trình cân chỉnh pin") { onCancelCalibration() }
                    }
                }

                // Forced Discharge Pill (CHIE)
                if state.isDischargeActive || state.isAllowDischargeEnabled || (state.snapshot?.isOnAC == true && (state.snapshot?.percent ?? 0) > state.chargeLimit) {
                    Button(action: onToggleAllowDischarge) {
                        HStack(spacing: 3.5) {
                            Image(systemName: state.isDischargeActive ? "bolt.badge.arrow.down.fill" : "arrow.down.to.line")
                                .font(.system(size: 10, weight: .semibold))
                            Text(state.isDischargeActive ? "Đang xả" : (state.isAllowDischargeEnabled ? "Tự xả: Bật" : "Xả pin"))
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            if state.isDischargeActive {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .foregroundStyle(state.isDischargeActive ? Color.orange : (state.isAllowDischargeEnabled ? NotchTokens.primaryText : NotchTokens.secondaryText))
                        .padding(.horizontal, 6)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(NotchTokens.fill(state.isDischargeActive ? 0.16 : (state.isAllowDischargeEnabled ? 0.10 : 0.04)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(NotchTokens.fill(state.isDischargeActive ? 0.35 : (state.isAllowDischargeEnabled ? 0.20 : 0.08)), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Top-Up Once (100% Boost)
                if state.isLimitToEightyEnabled {
                    Button(action: onToggleTopUp) {
                        HStack(spacing: 3.5) {
                            Image(systemName: "bolt.badge.clock.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(state.isTopUpOnceActive ? "Đang sạc 100%" : "Sạc 100%")
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(state.isTopUpOnceActive ? NotchTokens.primaryText : NotchTokens.secondaryText)
                        .padding(.horizontal, 6)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(NotchTokens.fill(state.isTopUpOnceActive ? 0.12 : 0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(NotchTokens.fill(state.isTopUpOnceActive ? 0.22 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Gentle Charging / Thermal Throttle Pill
            Button(action: onToggleGentle) {
                HStack(spacing: 3.5) {
                    Image(systemName: state.isThermalThrottled ? "thermometer.snowflake" : (state.isGentleChargingEnabled ? "thermometer.medium" : "thermometer"))
                        .font(.system(size: 10, weight: .semibold))
                    Text(state.isThermalThrottled ? "Hạ nhiệt" : (state.isGentleChargingEnabled ? "Sạc êm: Bật" : "Sạc êm"))
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    if state.isThermalThrottled {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4, height: 4)
                    }
                }
                .foregroundStyle(state.isThermalThrottled ? Color.orange : (state.isGentleChargingEnabled ? NotchTokens.primaryText : NotchTokens.secondaryText))
                .padding(.horizontal, 6)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(NotchTokens.fill(state.isThermalThrottled || state.isGentleChargingEnabled ? 0.12 : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(NotchTokens.fill(state.isThermalThrottled ? 0.35 : (state.isGentleChargingEnabled ? 0.22 : 0.08)), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Low Power Mode Quick Toggle
            Button(action: onToggleLowPower) {
                HStack(spacing: 3.5) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(state.isLowPowerMode ? "Tiết kiệm: Bật" : "Tiết kiệm")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(state.isLowPowerMode ? NotchTokens.primaryText : NotchTokens.secondaryText)
                .padding(.horizontal, 6)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(NotchTokens.fill(state.isLowPowerMode ? 0.12 : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(NotchTokens.fill(state.isLowPowerMode ? 0.22 : 0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Linear Telemetry Grid: High-density, 1px hairline zinc bordered cards displaying technical metrics.
/// Automatically splits into two balanced rows when metrics exceed 4 columns.
struct BatteryFactsRow: View {
    let facts: [BatteryFact]

    var body: some View {
        if facts.count <= 4 {
            singleRow(facts)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            twoRows
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func singleRow(_ items: [BatteryFact]) -> some View {
        HStack(spacing: 6) {
            ForEach(items) { fact in
                BatteryFactCell(fact: fact)
            }
        }
    }

    private var twoRows: some View {
        let half = (facts.count + 1) / 2
        let row1 = Array(facts.prefix(half))
        let row2 = Array(facts.dropFirst(half))
        return VStack(spacing: 6) {
            singleRow(row1)
                .frame(height: 31)
            singleRow(row2)
                .frame(height: 31)
        }
    }
}

/// High-density developer metric card: monospace value with regular metadata label.
struct BatteryFactCell: View {
    let fact: BatteryFact

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(fact.value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(fact.label)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(NotchTokens.fill(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(NotchTokens.fill(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fact.accessibilityLabel)
    }
}

/// Hardware guard status footer bar: Sleep drain telemetry, thermal safety, & calibration tracking.
struct BatteryFooterBar: View {
    let state: BatteryState

    var body: some View {
        HStack(spacing: 8) {
            // Sleep Guard status
            HStack(spacing: 4) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 9.5))
                if let drain = state.lastSleepDrain {
                    Text("Sleep Guard: Hao \(drain.drainPercent)% (\(Int(drain.duration / 3600))h)")
                } else {
                    Text("Sleep Guard: Sẵn sàng")
                }
            }

            Text("•")
                .foregroundStyle(NotchTokens.fill(0.35))

            // Calibration status
            if state.calibrationStage != .idle {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9.5))
                        .foregroundStyle(state.calibrationStage == .discharging ? Color.orange : Color.green)
                    Text("Cân pin: \(calibrationStepText)")
                        .foregroundStyle(state.calibrationStage == .discharging ? Color.orange : Color.green)
                }

                Text("•")
                    .foregroundStyle(NotchTokens.fill(0.35))
            } else if state.isLimitToEightyEnabled && state.isSailingEnabled {
                // Sailing Mode status
                HStack(spacing: 4) {
                    Image(systemName: "wind")
                        .font(.system(size: 9.5))
                    Text("Sailing: \(max(20, state.chargeLimit - state.sailingDelta))–\(state.chargeLimit)%")
                }

                Text("•")
                    .foregroundStyle(NotchTokens.fill(0.35))
            }

            // Thermal Guard status
            HStack(spacing: 4) {
                if state.isThermalThrottled {
                    Image(systemName: "thermometer.sun.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                    let tempStr = state.details?.temperatureCelsius.map { String(format: "%.1f°C", $0) } ?? ""
                    Text("Thermal: Hạ nhiệt (\(tempStr))")
                        .foregroundStyle(.orange)
                } else if let temp = state.details?.temperatureCelsius {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9.5))
                    Text("Thermal: \(String(format: "%.1f", temp))°C")
                } else {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9.5))
                    Text("Thermal: Tối ưu")
                }
            }

            Spacer()

            // Control backend badge
            Text(statusBadgeText)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(NotchTokens.fill(0.08)))
        }
        .font(.system(size: 9.5, weight: .regular))
        .foregroundStyle(NotchTokens.secondaryText)
        .lineLimit(1)
    }

    private var calibrationStepText: String {
        switch state.calibrationStage {
        case .topUp: return "Bước 1/3 (Sạc 100%)"
        case .discharging: return "Bước 2/3 (Xả 15%)"
        case .recharging: return "Bước 3/3 (Bù \(state.chargeLimit)%)"
        case .idle: return ""
        }
    }

    private var statusBadgeText: String {
        if state.calibrationStage != .idle {
            switch state.calibrationStage {
            case .topUp: return "Cân pin (1/3: Sạc)"
            case .discharging: return "Cân pin (2/3: Xả 15%)"
            case .recharging: return "Cân pin (3/3: Bù)"
            case .idle: break
            }
        }
        let isDischarging = (state.details?.batteryWatts ?? 0) < -0.5 || (state.details?.amperageMilliamps ?? 0) < -80
        let isTrulyPassthrough: Bool = {
            guard let snapshot = state.snapshot, (snapshot.isOnAC || snapshot.isAttachedToAdapter) else { return false }
            if isDischarging { return false }
            if snapshot.isCharging { return (state.details?.batteryWatts ?? 10.0) <= 0.5 }
            return abs(state.details?.batteryWatts ?? 0) <= 0.5
        }()
        if state.isDischargeActive {
            return "Xả pin (CHIE)"
        } else if state.isThermalThrottled {
            return "Thermal Guard"
        } else if state.isLimitToEightyEnabled {
            if isTrulyPassthrough {
                return "Giữ \(state.chargeLimit)% (Passthrough)"
            }
            if state.isInhibited && isDischarging {
                let delta = max(2, state.sailingDelta)
                return "Sailing \(max(20, state.chargeLimit - delta))–\(state.chargeLimit)%"
            }
            if (state.snapshot?.percent ?? 0) < state.chargeLimit {
                return "Sạc tới \(state.chargeLimit)%"
            }
            return "Khóa \(state.chargeLimit)%"
        } else {
            return state.chargeLimiter.state.hardwareInhibitAvailable ? "SMC Inhibit" : "Smart Guard"
        }
    }
}

/// Lock screen widget: the percent and nothing else.
struct BatteryLockScreenView: View {
    let state: BatteryState

    var body: some View {
        if let snapshot = state.snapshot {
            HStack(spacing: 10) {
                Image(systemName: Self.symbol(for: snapshot))
                    .font(.system(size: 22))
                Text("\(snapshot.percent)%")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(NotchTokens.primaryText)
            // The lock screen draws this on a black surface of its own, whatever the look.
            .notchOnDarkBackground()
        }
    }

    static func symbol(for snapshot: PowerSourceSnapshot) -> String {
        if snapshot.isCharging { return "battery.100percent.bolt" }
        return switch snapshot.percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

struct BatteryActivityIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
    }
}

struct BatteryActivityPercent: View {
    let percent: Int
    let tint: Color

    var body: some View {
        Text("\(percent)%")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct BatterySettingsView: View {
    @Binding var lowThreshold: Int
    let lowThresholdRange: ClosedRange<Int>
    @Binding var notifyOnCharge: Bool
    @Binding var notifyAtEighty: Bool
    @Binding var limitToEighty: Bool
    @Binding var chargeLimit: Int
    @Binding var sailingMode: Bool
    @Binding var sailingDelta: Int
    @Binding var allowDischarge: Bool
    @Binding var syncMagSafeLED: Bool
    @Binding var calibrationIntervalDays: Int
    let lastCalibrationTimestamp: Double
    let calibrationStage: BatteryCalibrationStage
    let onStartCalibration: () -> Void
    let onCancelCalibration: () -> Void
    @Binding var sleepDrainAlert: Bool
    @Binding var bypassMode: Bool
    @Binding var gentleCharging: Bool
    var helperStatus: SMCHelperStatus = .enabled
    var onRegisterHelper: () -> Void = {}
    var onOpenSystemSettings: () -> Void = {}
    var onRefreshHelperStatus: () -> Void = {}

    var body: some View {
        Group {
            // Hardware Privileged Helper card
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 13))
                        .foregroundStyle(helperStatus == .enabled ? .green : .secondary)
                    Text("Helper phần cứng (Root Privileged Daemon)")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    switch helperStatus {
                    case .enabled:
                        Text("Đang hoạt động (Root)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.12)))
                    case .requiresApproval:
                        Text("Cần cấp quyền")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.12)))
                    case .notInstalled, .notFound:
                        Text("Chưa cài đặt")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)))
                    }
                }

                Text("Quyền Root cần thiết để can thiệp thanh ghi SMC (BCLM, CHTE, CHIE) ngắt dòng nạp pin trực tiếp.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if helperStatus == .notInstalled || helperStatus == .notFound {
                        Button("Cài helper phần cứng") {
                            onRegisterHelper()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Text("Đăng ký vào hệ thống, sau đó cho phép trong Cài đặt hệ thống > Mục đăng nhập")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if helperStatus == .requiresApproval {
                        Button("Mở Cài đặt hệ thống (Mục đăng nhập)") {
                            onOpenSystemSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Đã cho phép, làm mới") {
                            onRefreshHelperStatus()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if helperStatus == .enabled {
                        Text("✓ SMC Inhibit sẵn sàng ngắt nạp phần cứng (+0 W khi khóa)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 4)
            .task {
                while !Task.isCancelled {
                    if helperStatus != .enabled {
                        onRefreshHelperStatus()
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }

            Stepper("Ngưỡng pin yếu: \(lowThreshold)%", value: $lowThreshold, in: lowThresholdRange, step: 5)

            Toggle(isOn: $notifyOnCharge) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thông báo khi cắm sạc")
                    Text("Gửi thông báo và hiện Live Activity khi cắm nguồn MagSafe/USB-C")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $notifyAtEighty) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nhắc rút sạc khi chạm 80%")
                    Text("Bảo vệ tuổi thọ cell pin lithium-ion khi sạc thông thường")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $limitToEighty) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kiểm soát nguồn sạc tối đa (Max Charge Limit)")
                    Text("Tự động phối hợp macOS Passthrough và Sailing thông minh để giữ pin ở mức giới hạn")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if limitToEighty {
                Stepper("Giới hạn mức sạc: \(chargeLimit)%", value: $chargeLimit, in: 50...100, step: 5)

                Toggle(isOn: $sailingMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chế độ thả buồm (Sailing Mode)")
                        Text("Chống vi chu kỳ micro-charging liên tục khi cắm sạc cố định")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if sailingMode {
                    Stepper(
                        "Biên độ thả buồm: \(sailingDelta)% (Sạc lại khi tụt xuống \(max(20, chargeLimit - sailingDelta))%)",
                        value: $sailingDelta,
                        in: 2...20,
                        step: 1
                    )
                }

                Toggle(isOn: $allowDischarge) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tự động xả về ngưỡng sạc (Automatic Discharge)")
                        Text("Tự động ngắt sạc và xả pin về mức giới hạn khi pin sạc vượt ngưỡng (qua SMC CHIE)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $syncMagSafeLED) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Đồng bộ đèn LED cáp sạc MagSafe")
                        Text("Đổi đèn LED từ Cam sang Xanh lá khi pin đạt giới hạn sạc (ACLC)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Picker("Chu kỳ cân chỉnh pin định kỳ (Calibration Mode)", selection: $calibrationIntervalDays) {
                    Text("Tắt (Thủ công)").tag(0)
                    Text("Mỗi 14 ngày").tag(14)
                    Text("Mỗi 30 ngày (Khuyến nghị)").tag(30)
                    Text("Mỗi 60 ngày").tag(60)
                }

                LabeledContent("Lần cân chỉnh gần nhất") {
                    if lastCalibrationTimestamp > 0 {
                        let date = Date(timeIntervalSince1970: lastCalibrationTimestamp)
                        Text(date.formatted(date: .numeric, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Chưa từng thực hiện")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if calibrationStage == .idle {
                    Button("Bắt đầu chu trình cân chỉnh pin ngay (100% ➔ 15% ➔ Bù)") {
                        onStartCalibration()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Hủy chu trình cân chỉnh pin", role: .destructive) {
                        onCancelCalibration()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Toggle(isOn: $gentleCharging) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sạc êm khi pin nóng (Thermal Guard)")
                    Text("Tự động ngắt sạc khi nhiệt độ cell pin vượt quá 34°C để bảo vệ pin")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $sleepDrainAlert) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cảnh báo hao pin bất thường khi ngủ")
                    Text("Phát hiện tiến trình ngầm tiêu hao năng lượng khi gập máy")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
