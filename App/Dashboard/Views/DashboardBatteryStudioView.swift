import BatteryModule
import MyNotchCore
import SwiftUI

/// Dedicated full-screen workspace for Battery Management & Telemetry (AlDente Pro Parity).
/// Connected directly to AppleSMC hardware registers and BatteryModule runtime.
struct DashboardBatteryStudioView: View {
    let telemetry: DashboardTelemetryCenter
    let registry: ModuleRegistry

    @State private var chargeLimit: Double = 80
    @State private var isBypassActive: Bool = false
    @State private var isDischargeActive: Bool = false
    @State private var isDischargeEnabled: Bool = false
    @State private var isSailingActive: Bool = true
    @State private var isHeatProtectionActive: Bool = true
    @State private var isTopUpActive: Bool = false
    @State private var isCalibrationActive: Bool = false

    // MARK: - Automated Schedule States
    @State private var isScheduleEnabled: Bool = false
    @State private var activeScheduleRuleTitle: String? = nil
    @State private var scheduleRules: [BatteryScheduleRule] = []
    @State private var isEditingSchedule: Bool = false
    @State private var editingRuleId: UUID? = nil
    @State private var editTitle: String = ""
    @State private var editDays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var editStartHour: Int = 8
    @State private var editStartMinute: Int = 0
    @State private var editEndHour: Int = 18
    @State private var editEndMinute: Int = 0
    @State private var editActionMode: Int = 0 // 0: Limit, 1: Discharge, 2: Sailing, 3: TopUp
    @State private var editTargetPercent: Int = 80

    // MARK: - Battery Activity History States
    @State private var selectedHistoryRange: BatteryHistoryRange = .last24Hours
    @State private var hoveredPoint: BatteryHistoryPoint? = nil
    @State private var hoverLocationX: CGFloat? = nil

    private var batteryModule: BatteryModule? {
        registry.module(for: "battery") as? BatteryModule
    }

    private var batterySnapshot: DashboardSnapshot? {
        telemetry.batterySnapshot
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // Section 1: Real-time Telemetry Metrics
                telemetryCardsGrid

                // Section 2: Interactive SMC Power Controls (AlDente Parity)
                powerControlsSection

                // Section 3: Advanced Automation & Health Insights
                automationAndHealthSection
            }
            .padding(20)
        }
        .background(DashboardTheme.canvasBackground)
        .onAppear {
            syncStateFromModule()
        }
    }

    // MARK: - Section 1: Telemetry Cards Grid

    // MARK: - Telemetry Cards Grid

    private var telemetryCardsGrid: some View {
        let status = batteryModule?.studioStatus()
        let percent = status?.percent ?? (batterySnapshot?.metric(named: "Dung lượng")?.value.numberValue.map(Int.init) ?? 98)
        let powerText = status != nil ? (status!.isOnAC ? (status!.isCharging ? "Đang sạc (AC)" : "Nguồn ngoài (AC)") : "Dùng pin") : "Nguồn ngoài (AC)"
        let watts = status?.batteryWatts ?? (batterySnapshot?.metric(named: "Công suất")?.value.numberValue ?? 60.2)
        let temp = status?.tempCelsius ?? (batterySnapshot?.metric(named: "Nhiệt độ")?.value.numberValue ?? 31.5)
        let health = status?.healthPercent ?? (
            batterySnapshot?.metric(named: "Độ chai pin")?.value.numberValue.map(Int.init)
            ?? batterySnapshot?.metric(named: "Độ chai")?.value.numberValue.map(Int.init)
        )
        let cycles = status?.cycleCount.map(String.init)
            ?? batterySnapshot?.metric(named: "Chu kỳ sạc")?.value.numberValue.map { "\(Int($0))" }
            ?? "--"

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            // Mức Pin & Trạng thái sạc
            DashboardMetricCard(
                label: "Mức Pin Hiện Tại",
                value: "\(percent)",
                unit: "%",
                icon: percent > 20 ? "battery.100percent.bolt" : "battery.25percent",
                iconColor: DashboardTheme.batteryGreen,
                level: percent <= 20 ? .warning : .normal,
                subtitle: powerText
            )

            // Công suất dòng điện
            DashboardMetricCard(
                label: "Công Suất Nguồn",
                value: String(format: "%.1f", abs(watts)),
                unit: "W",
                icon: "bolt.badge.automatic",
                iconColor: DashboardTheme.hardwareCoral,
                level: .normal,
                subtitle: isBypassActive ? "Bypass (Nuôi máy)" : "Củ sạc MagSafe / Type-C"
            )

            // Nhiệt độ Cell Pin
            DashboardMetricCard(
                label: "Nhiệt Độ Cell",
                value: String(format: "%.1f", temp),
                unit: "°C",
                icon: "thermometer.medium",
                iconColor: temp >= 34 ? DashboardTheme.statusCritical : DashboardTheme.batteryGreen,
                level: temp >= 34 ? .warning : .normal,
                subtitle: temp >= 34 ? "Nóng (Đang ngắt sạc)" : "Mát mẻ (Lý tưởng)"
            )

            // Sức Khỏe & Chu Kỳ
            DashboardMetricCard(
                label: "Sức Khỏe Pin",
                value: health != nil ? "\(health!)" : "--",
                unit: health != nil ? "%" : "",
                icon: "heart.fill",
                iconColor: DashboardTheme.habitViolet,
                level: .normal,
                subtitle: cycles != "--" ? "Chu kỳ sạc: \(cycles) lần" : "Chưa có dữ liệu chu kỳ"
            )
        }
    }

    // MARK: - SMC Power Controls Section

    private var powerControlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardSectionHeader(
                title: "Bảng Điều Khiển Nguồn Phần Cứng (SMC Controls)",
                subtitle: "Can thiệp trực tiếp thanh ghi CH0I, BCLM, CHIE"
            )

            VStack(spacing: 16) {
                // 1. Slider Giới Hạn Sạc (Charge Limiter)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Giới Hạn Sạc Phần Cứng (Charge Limit)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DashboardTheme.textPrimary)
                            Text("Khóa sạc tại ngưỡng an toàn để tối đa hóa tuổi thọ hóa học của pin")
                                .font(.system(size: 11.5))
                                .foregroundColor(DashboardTheme.textMuted)
                        }

                        Spacer()

                        Text("\(Int(chargeLimit))%")
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(DashboardTheme.infoAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(DashboardTheme.infoAccent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    HStack(spacing: 14) {
                        Slider(
                            value: $chargeLimit,
                            in: 50...100,
                            step: 5,
                            onEditingChanged: { isEditing in
                                if !isEditing {
                                    batteryModule?.setChargeLimit(Int(chargeLimit))
                                    syncStateFromModule()
                                }
                            }
                        )
                        .accentColor(DashboardTheme.infoAccent)

                        HStack(spacing: 6) {
                            limitPresetButton(60)
                            limitPresetButton(80)
                            limitPresetButton(100)
                        }
                    }
                }
                .dashboardCard()

                // 2. Chế độ điều khiển nâng cao (AlDente Parity Toggles - Lưới 3x2 toàn diện)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    
                    // Hardware Bypass Mode
                    controlToggleCard(
                        title: "Nuôi Nguồn Trực Tiếp (Hardware Bypass)",
                        description: "Ngắt dòng nạp pin khi cắm sạc, cấp điện hoàn toàn từ củ sạc vào bo mạch chủ để chống chai và phồng pin khi render/build nặng.",
                        icon: "bolt.shield.fill",
                        iconColor: DashboardTheme.batteryGreen,
                        isActive: $isBypassActive,
                        badgeText: isBypassActive ? "Đang bật" : "Tắt"
                    ) {
                        toggleBypass()
                    }

                    // Smart Discharge Mode
                    controlToggleCard(
                        title: "Xả Pin Cưỡng Bức (Force Discharge)",
                        description: "Xả pin từ mức hiện tại xuống ngưỡng giới hạn (\(Int(chargeLimit))%) ngay cả khi đang cắm sạc liên tục nhiều ngày.",
                        icon: "arrow.down.circle.fill",
                        iconColor: DashboardTheme.hardwareCoral,
                        isActive: $isDischargeEnabled,
                        badgeText: isDischargeActive ? "Đang xả pin" : (isDischargeEnabled ? "Đã bật (Tự xả khi > \(Int(chargeLimit))%)" : "Tắt")
                    ) {
                        toggleDischarge()
                    }

                    // Sailing Mode
                    controlToggleCard(
                        title: "Chế Độ Đi Thuyền (Sailing Mode)",
                        description: "Cho phép mức pin trôi tự nhiên 5% trước khi bắt đầu nạp lại (ví dụ 75% -> 80%), loại bỏ hoàn toàn vi chu kỳ sạc ngắt liên tục.",
                        icon: "water.waves",
                        iconColor: DashboardTheme.todoBlue,
                        isActive: $isSailingActive,
                        badgeText: isSailingActive ? "Biên độ 5%" : "Tắt"
                    ) {
                        toggleSailing()
                    }

                    // Top Up Once
                    controlToggleCard(
                        title: "Sạc Đầy Tạm Thời (Top Up 100% Boost)",
                        description: "1-click nạp đầy 100% một lần duy nhất trước khi mang máy ra ngoài. Tự động trả về giới hạn an toàn sau khi rút sạc.",
                        icon: "battery.100percent.circle.fill",
                        iconColor: DashboardTheme.habitViolet,
                        isActive: $isTopUpActive,
                        badgeText: isTopUpActive ? "Đang sạc 100%" : "Sẵn sàng"
                    ) {
                        toggleTopUp()
                    }

                    // Heat Protection
                    controlToggleCard(
                        title: "Bảo Vệ Quá Nhiệt (Heat Protection)",
                        description: "Tự động ngắt dòng sạc khi nhiệt độ cell pin vượt quá 34°C lúc CPU tải nặng, và tiếp tục sạc khi máy hạ nhiệt dưới 31°C.",
                        icon: "thermometer.snowflake",
                        iconColor: DashboardTheme.statusCritical,
                        isActive: $isHeatProtectionActive,
                        badgeText: isHeatProtectionActive ? "Ngưỡng 34°C" : "Tắt"
                    ) {
                        toggleHeatProtection()
                    }

                    // Calibration Cycle
                    controlToggleCard(
                        title: "Chu Kỳ Hiệu Chuẩn Pin (Calibration)",
                        description: "Tự động sạc đầy 100%, ngâm điện, xả chậm xuống 15% rồi sạc lại 80% để chip Gas Gauge của Apple nhận diện chính xác dung lượng.",
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        iconColor: DashboardTheme.infoAccent,
                        isActive: $isCalibrationActive,
                        badgeText: isCalibrationActive ? "Đang hiệu chuẩn" : "1 lần / tháng"
                    ) {
                        toggleCalibration()
                    }

                }

            }
        }
    }

    // MARK: - Automation & Health Section

    private var automationAndHealthSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Lên Lịch Tự Động & Lịch Sử (Schedule & Lifecycle)",
                subtitle: "Tự động hóa theo lịch làm việc và theo dõi lịch sử nạp/xả pin"
            )

            // Biểu đồ lịch sử hoạt động pin
            batteryActivityHistoryCard

            HStack(alignment: .top, spacing: 16) {
                // Interactive Schedule Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(DashboardTheme.infoAccent)
                            Text("Quy Tắc Lên Lịch Tuần")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(DashboardTheme.textPrimary)
                        }

                        // Active status pill
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isScheduleEnabled ? DashboardTheme.batteryGreen : DashboardTheme.textMuted)
                                .frame(width: 6, height: 6)
                            Text(isScheduleEnabled ? (activeScheduleRuleTitle ?? "Đang chạy") : "Tắt")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(isScheduleEnabled ? DashboardTheme.batteryGreen : DashboardTheme.textSecondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(isScheduleEnabled ? DashboardTheme.batteryGreen.opacity(0.12) : DashboardTheme.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        Spacer()

                        // Master Toggle
                        Button(action: toggleMasterSchedule) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(isScheduleEnabled ? DashboardTheme.batteryGreen : DashboardTheme.textMuted)
                                    .frame(width: 7, height: 7)
                                Text(isScheduleEnabled ? "BẬT" : "TẮT")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(isScheduleEnabled ? DashboardTheme.batteryGreen : DashboardTheme.textSecondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(isScheduleEnabled ? DashboardTheme.batteryGreen.opacity(0.12) : DashboardTheme.chipBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isScheduleEnabled ? DashboardTheme.batteryGreen.opacity(0.35) : DashboardTheme.hairlineBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        // Add Rule Button
                        Button(action: startAddingRule) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Thêm lịch")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DashboardTheme.infoAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }

                    // Rules List
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(scheduleRules) { rule in
                            HStack(alignment: .center, spacing: 8) {
                                Button(action: { toggleScheduleRule(rule) }) {
                                    Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(rule.isEnabled ? DashboardTheme.infoAccent : DashboardTheme.textMuted)
                                        .font(.system(size: 13))
                                }
                                .buttonStyle(.plain)

                                Text(rule.daysDisplayString)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(DashboardTheme.textPrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DashboardTheme.chipBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))

                                Text(rule.timeRangeString)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(DashboardTheme.textSecondary)

                                Text(rule.title)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(DashboardTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                Text(rule.action.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(DashboardTheme.infoAccent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(DashboardTheme.infoAccent.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))

                                Button(action: { startEditingRule(rule) }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(DashboardTheme.textSecondary)
                                        .padding(3)
                                }
                                .buttonStyle(.plain)

                                Button(action: { deleteScheduleRule(rule) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(DashboardTheme.textMuted)
                                        .padding(3)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    // Inline Rule Editor
                    if isEditingSchedule {
                        VStack(alignment: .leading, spacing: 10) {
                            Rectangle()
                                .fill(DashboardTheme.separator)
                                .frame(height: 1)

                            HStack {
                                Text(editingRuleId != nil ? "Chỉnh Sửa Quy Tắc Lên Lịch" : "Thêm Quy Tắc Lên Lịch Mới")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(DashboardTheme.textPrimary)
                                Spacer()
                            }

                            HStack(spacing: 8) {
                                Text("Tên quy tắc:")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(DashboardTheme.textSecondary)
                                    .frame(width: 80, alignment: .leading)
                                TextField("Tên quy tắc", text: $editTitle)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5))
                            }

                            HStack(spacing: 8) {
                                Text("Ngày áp dụng:")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(DashboardTheme.textSecondary)
                                    .frame(width: 80, alignment: .leading)
                                HStack(spacing: 4) {
                                    ForEach([(2, "T2"), (3, "T3"), (4, "T4"), (5, "T5"), (6, "T6"), (7, "T7"), (1, "CN")], id: \.0) { day, name in
                                        Button(action: {
                                            if editDays.contains(day) {
                                                if editDays.count > 1 { editDays.remove(day) }
                                            } else {
                                                editDays.insert(day)
                                            }
                                        }) {
                                            Text(name)
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundColor(editDays.contains(day) ? Color.white : DashboardTheme.textSecondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(editDays.contains(day) ? DashboardTheme.infoAccent : DashboardTheme.chipBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            HStack(spacing: 16) {
                                HStack(spacing: 6) {
                                    Text("Từ:")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(DashboardTheme.textSecondary)
                                    Text(String(format: "%02d:%02d", editStartHour, editStartMinute))
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    Stepper("", value: $editStartHour, in: 0...23)
                                        .labelsHidden()
                                }

                                HStack(spacing: 6) {
                                    Text("Đến:")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(DashboardTheme.textSecondary)
                                    Text(String(format: "%02d:%02d", editEndHour, editEndMinute))
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    Stepper("", value: $editEndHour, in: 0...23)
                                        .labelsHidden()
                                }
                            }

                            HStack(spacing: 8) {
                                Text("Hành động:")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(DashboardTheme.textSecondary)
                                    .frame(width: 80, alignment: .leading)

                                Picker("", selection: $editActionMode) {
                                    Text("Khóa sạc").tag(0)
                                    Text("Xả pin").tag(1)
                                    Text("Đi thuyền").tag(2)
                                    Text("Sạc 100%").tag(3)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 270)

                                if editActionMode == 0 || editActionMode == 1 || editActionMode == 2 {
                                    HStack(spacing: 4) {
                                        Text("Mức:")
                                            .font(.system(size: 11))
                                            .foregroundColor(DashboardTheme.textSecondary)
                                        Text("\(editTargetPercent)%")
                                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(DashboardTheme.infoAccent)
                                        Stepper("", value: $editTargetPercent, in: 50...95, step: 5)
                                            .labelsHidden()
                                    }
                                    .padding(.leading, 6)
                                }
                            }

                            HStack {
                                Spacer()
                                Button("Hủy") {
                                    isEditingSchedule = false
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5))
                                .foregroundColor(DashboardTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)

                                Button("Lưu & Áp Dụng") {
                                    saveEditingRule()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Color.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(DashboardTheme.infoAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        .padding(10)
                        .background(DashboardTheme.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .dashboardCard()

                // Health Insights Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundColor(DashboardTheme.batteryGreen)
                        Text("Khuyến Nghị Kỹ Thuật")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DashboardTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Mức sạc 80% giảm tốc độ thoái hóa cathode xuống 3 lần so với 100%.")
                            .font(.system(size: 12))
                            .foregroundColor(DashboardTheme.textSecondary)
                        Text("• Bypass mode ngắt hoàn toàn chu kỳ sạc vi lượng khi bạn cắm sạc màn hình ngoài.")
                            .font(.system(size: 12))
                            .foregroundColor(DashboardTheme.textSecondary)
                        Text("• Đã thiết lập sàn an toàn 20% ngăn cạn pin trong mọi chế độ xả.")
                            .font(.system(size: 12))
                            .foregroundColor(DashboardTheme.textSecondary)
                    }
                }
                .dashboardCard()
            }
        }
    }

    // MARK: - Battery Activity History Card

    private var batteryActivityHistoryCard: some View {
        let historyStore = batteryModule?.historyStore
        let rawPoints = historyStore?.points(for: selectedHistoryRange) ?? []
        let currentStatus = batteryModule?.studioStatus()
        let currentPercent = currentStatus?.percent ?? (batterySnapshot?.metric(named: "Dung lượng")?.value.numberValue.map(Int.init) ?? 80)
        let currentWatts = currentStatus?.batteryWatts ?? 0.0

        let points = rawPoints
        let summary = historyStore?.summary(for: selectedHistoryRange) ?? BatteryHistorySummary(
            minPercent: currentPercent,
            maxPercent: currentPercent,
            averagePercent: currentPercent,
            peakWatts: abs(currentWatts),
            sampleCount: 0,
            dischargingMinutes: 0
        )

        return VStack(alignment: .leading, spacing: 14) {
            // Header: Title + Range Switcher
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DashboardTheme.infoAccent)
                    Text("Lịch Sử Hoạt Động & Mức Nạp Pin")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(DashboardTheme.textPrimary)
                }

                Spacer()

                // Range Selector (24 Giờ / 7 Ngày)
                HStack(spacing: 4) {
                    ForEach(BatteryHistoryRange.allCases) { range in
                        Button(action: { selectedHistoryRange = range }) {
                            Text(range.title)
                                .font(.system(size: 11, weight: selectedHistoryRange == range ? .bold : .medium))
                                .foregroundColor(selectedHistoryRange == range ? DashboardTheme.textPrimary : DashboardTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(selectedHistoryRange == range ? DashboardTheme.controlBackground : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(selectedHistoryRange == range ? DashboardTheme.controlBorder : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2.5)
                .background(DashboardTheme.segmentTrackBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // Summary Stats Row (4 metrics)
            HStack(spacing: 12) {
                historyStatMetric(label: "Biên Độ Sạc", value: points.isEmpty ? "--" : "\(summary.minPercent)% – \(summary.maxPercent)%", icon: "arrow.up.and.down", color: DashboardTheme.infoAccent)
                historyStatMetric(label: "Mức Trung Bình", value: points.isEmpty ? "--" : "\(summary.averagePercent)%", icon: "equal", color: DashboardTheme.batteryGreen)
                historyStatMetric(label: "Công Suất Đỉnh", value: points.isEmpty ? "--" : String(format: "%.1f W", summary.peakWatts), icon: "bolt.badge.automatic", color: DashboardTheme.hardwareCoral)
                historyStatMetric(label: "Mẫu Đo / Xả Pin", value: "\(summary.sampleCount) mẫu • \(summary.dischargingMinutes)p xả", icon: "clock.arrow.circlepath", color: DashboardTheme.textSecondary)
            }

            if points.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22))
                        .foregroundColor(DashboardTheme.textMuted)
                    Text("Đang đồng bộ dữ liệu lịch sử hoạt động từ hệ thống...")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(DashboardTheme.textMuted)
                    Text("Biểu đồ sẽ xuất hiện ngay khi ghi nhận các mốc nạp/xả pin thực tế")
                        .font(.system(size: 10.5))
                        .foregroundColor(DashboardTheme.textSecondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(DashboardTheme.chipBackground.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DashboardTheme.hairlineBorder.opacity(0.5), lineWidth: 1)
                )
            } else {
                // Interactive Chart Canvas
                BatteryHistoryCanvasView(
                    points: points,
                    range: selectedHistoryRange,
                    chargeLimit: chargeLimit,
                    hoveredPoint: $hoveredPoint,
                    hoverLocationX: $hoverLocationX
                )
                .frame(height: 180)
            }
        }
        .dashboardCard()
    }

    private func historyStatMetric(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DashboardTheme.textMuted)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(DashboardTheme.textPrimary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DashboardTheme.chipBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Component Helpers

    private func limitPresetButton(_ preset: Int) -> some View {
        Button(action: {
            self.chargeLimit = Double(preset)
            batteryModule?.setChargeLimit(preset)
            syncStateFromModule()
        }) {
            Text("\(preset)%")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Int(chargeLimit) == preset ? Color.white : DashboardTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Int(chargeLimit) == preset ? DashboardTheme.infoAccent : DashboardTheme.chipBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func controlToggleCard(
        title: String,
        description: String,
        icon: String,
        iconColor: Color,
        isActive: Binding<Bool>,
        badgeText: String,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(iconColor)
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DashboardTheme.textPrimary)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(isActive.wrappedValue ? iconColor : DashboardTheme.textMuted)
                            .frame(width: 7, height: 7)
                        Text(isActive.wrappedValue ? "BẬT" : "TẮT")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(isActive.wrappedValue ? iconColor : DashboardTheme.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isActive.wrappedValue ? iconColor.opacity(0.12) : DashboardTheme.chipBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(isActive.wrappedValue ? iconColor.opacity(0.35) : DashboardTheme.hairlineBorder, lineWidth: 1))
                }

                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundColor(DashboardTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                HStack {
                    Text(badgeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isActive.wrappedValue ? DashboardTheme.infoAccent : DashboardTheme.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isActive.wrappedValue ? DashboardTheme.infoAccent.opacity(0.12) : DashboardTheme.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dashboardCard()
    }

    // MARK: - Actions (Calling Real BatteryModule)

    private func syncStateFromModule() {
        if let status = batteryModule?.studioStatus() {
            chargeLimit = Double(status.chargeLimit)
            isBypassActive = status.isBypassEnabled
            isDischargeActive = status.isDischargeActive
            isDischargeEnabled = status.isAllowDischargeEnabled
            isSailingActive = status.isSailingEnabled
            isTopUpActive = status.isTopUpActive
            isHeatProtectionActive = status.isHeatProtectionEnabled
            isCalibrationActive = status.isCalibrationActive
            isScheduleEnabled = status.isScheduleEnabled
            activeScheduleRuleTitle = status.activeScheduleRuleTitle
            scheduleRules = batteryModule?.scheduleEngine.rules ?? []
        } else if let limitMetric = batterySnapshot?.metric(named: "Khóa sạc") {
            if limitMetric.value.displayString.contains("80") {
                chargeLimit = 80
            }
        }
    }

    private func toggleBypass() {
        batteryModule?.toggleBypassMode()
        syncStateFromModule()
    }

    private func toggleDischarge() {
        batteryModule?.toggleAllowDischarge()
        syncStateFromModule()
    }

    private func toggleSailing() {
        batteryModule?.toggleSailing()
        syncStateFromModule()
    }

    private func toggleTopUp() {
        batteryModule?.toggleTopUpOnce()
        syncStateFromModule()
    }

    private func toggleHeatProtection() {
        batteryModule?.toggleGentleCharging()
        syncStateFromModule()
    }

    private func toggleCalibration() {
        if isCalibrationActive {
            batteryModule?.cancelCalibration()
        } else {
            batteryModule?.startCalibration()
        }
        syncStateFromModule()
    }

    // MARK: - Schedule Handlers

    private func toggleMasterSchedule() {
        guard let module = batteryModule else { return }
        let next = !isScheduleEnabled
        module.setScheduleEnabled(next)
        syncStateFromModule()
    }

    private func toggleScheduleRule(_ rule: BatteryScheduleRule) {
        guard let module = batteryModule else { return }
        module.scheduleEngine.toggleRule(id: rule.id)
        if isScheduleEnabled {
            _ = module.scheduleEngine.applyActiveRule(at: Date(), to: module, force: true)
        }
        syncStateFromModule()
    }

    private func deleteScheduleRule(_ rule: BatteryScheduleRule) {
        guard let module = batteryModule else { return }
        module.scheduleEngine.deleteRule(id: rule.id)
        if isScheduleEnabled {
            _ = module.scheduleEngine.applyActiveRule(at: Date(), to: module, force: true)
        }
        syncStateFromModule()
    }

    private func startAddingRule() {
        editingRuleId = nil
        editTitle = "Quy tắc mới"
        editDays = [2, 3, 4, 5, 6]
        editStartHour = 8
        editStartMinute = 0
        editEndHour = 18
        editEndMinute = 0
        editActionMode = 0
        editTargetPercent = 80
        isEditingSchedule = true
    }

    private func startEditingRule(_ rule: BatteryScheduleRule) {
        editingRuleId = rule.id
        editTitle = rule.title
        editDays = Set(rule.daysOfWeek)
        editStartHour = rule.startHour
        editStartMinute = rule.startMinute
        editEndHour = rule.endHour
        editEndMinute = rule.endMinute
        switch rule.action {
        case .chargeLimit(let limit):
            editActionMode = 0
            editTargetPercent = limit
        case .forceDischarge(let target):
            editActionMode = 1
            editTargetPercent = target
        case .sailing(let lower, _):
            editActionMode = 2
            editTargetPercent = lower
        case .topUp100:
            editActionMode = 3
            editTargetPercent = 100
        }
        isEditingSchedule = true
    }

    private func saveEditingRule() {
        guard let module = batteryModule else { return }
        let action: BatteryScheduleAction
        switch editActionMode {
        case 0:
            action = .chargeLimit(editTargetPercent)
        case 1:
            action = .forceDischarge(target: editTargetPercent)
        case 2:
            action = .sailing(lower: max(50, editTargetPercent), upper: min(100, editTargetPercent + 10))
        case 3:
            action = .topUp100
        default:
            action = .chargeLimit(80)
        }

        let rule = BatteryScheduleRule(
            id: editingRuleId ?? UUID(),
            title: editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Quy tắc lên lịch" : editTitle,
            isEnabled: true,
            daysOfWeek: Array(editDays).sorted(),
            startHour: editStartHour,
            startMinute: editStartMinute,
            endHour: editEndHour,
            endMinute: editEndMinute,
            action: action
        )

        if editingRuleId != nil {
            module.scheduleEngine.updateRule(rule)
        } else {
            module.scheduleEngine.addRule(rule)
        }

        if isScheduleEnabled {
            _ = module.scheduleEngine.applyActiveRule(at: Date(), to: module, force: true)
        }
        isEditingSchedule = false
        syncStateFromModule()
    }
}

// MARK: - Battery History Canvas & Plotter

struct BatteryHistoryCanvasView: View {
    let points: [BatteryHistoryPoint]
    let range: BatteryHistoryRange
    let chargeLimit: Double
    @Binding var hoveredPoint: BatteryHistoryPoint?
    @Binding var hoverLocationX: CGFloat?

    private var timeTickLabels: [(Double, String)] {
        switch range {
        case .last24Hours:
            return [
                (0.0, "-24h"),
                (0.25, "-18h"),
                (0.50, "-12h"),
                (0.75, "-6h"),
                (1.0, "Bây giờ")
            ]
        case .last7Days:
            return [
                (0.0, "-7d"),
                (0.25, "-5d"),
                (0.50, "-3d"),
                (0.75, "-1d"),
                (1.0, "Hôm nay")
            ]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let leftPadding: CGFloat = 36
            let rightPadding: CGFloat = 16
            let topPadding: CGFloat = 12
            let bottomPadding: CGFloat = 22
            let plotWidth = max(10, width - leftPadding - rightPadding)
            let plotHeight = max(10, height - topPadding - bottomPadding)

            ZStack(alignment: .topLeading) {
                // Background Card Grid
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Spacer()
                        Rectangle()
                            .fill(DashboardTheme.hairlineBorder.opacity(0.35))
                            .frame(height: 1)
                    }
                    Spacer()
                }
                .padding(.leading, leftPadding)
                .padding(.trailing, rightPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)

                // Y-Axis Labels
                VStack(alignment: .trailing) {
                    Text("100%").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(DashboardTheme.textMuted)
                    Spacer()
                    Text("75%").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(DashboardTheme.textMuted)
                    Spacer()
                    Text("50%").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(DashboardTheme.textMuted)
                    Spacer()
                    Text("25%").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(DashboardTheme.textMuted)
                    Spacer()
                    Text("0%").font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(DashboardTheme.textMuted)
                }
                .frame(width: leftPadding - 6, height: plotHeight)
                .padding(.top, topPadding)

                // Charge Limit Reference Line
                let limitY = topPadding + plotHeight * (1.0 - CGFloat(chargeLimit) / 100.0)
                HStack(spacing: 4) {
                    BatteryHistoryDashedLine()
                        .stroke(DashboardTheme.batteryGreen.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(height: 1)
                    Text("Ngưỡng \(Int(chargeLimit))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(DashboardTheme.batteryGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(DashboardTheme.batteryGreen.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .padding(.leading, leftPadding)
                .padding(.trailing, rightPadding)
                .offset(y: limitY - 7)

                // Chart Path & Fill Area
                if points.count >= 2 {
                    let now = Date()
                    let startTime = now.addingTimeInterval(-range.duration).timeIntervalSince1970
                    let totalDuration = range.duration

                    let coords: [CGPoint] = points.map { pt in
                        let progress = max(0.0, min(1.0, (pt.timestamp.timeIntervalSince1970 - startTime) / totalDuration))
                        let x = leftPadding + plotWidth * CGFloat(progress)
                        let y = topPadding + plotHeight * (1.0 - CGFloat(pt.percent) / 100.0)
                        return CGPoint(x: x, y: y)
                    }

                    // Gradient Area Fill
                    Path { path in
                        guard let first = coords.first else { return }
                        path.move(to: CGPoint(x: first.x, y: topPadding + plotHeight))
                        path.addLine(to: first)
                        for pt in coords.dropFirst() {
                            path.addLine(to: pt)
                        }
                        if let last = coords.last {
                            path.addLine(to: CGPoint(x: last.x, y: topPadding + plotHeight))
                        }
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                DashboardTheme.batteryGreen.opacity(0.20),
                                DashboardTheme.batteryGreen.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line Stroke
                    Path { path in
                        guard let first = coords.first else { return }
                        path.move(to: first)
                        for pt in coords.dropFirst() {
                            path.addLine(to: pt)
                        }
                    }
                    .stroke(
                        DashboardTheme.batteryGreen,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    // Hover Indicator and Tooltip
                    if let _ = hoverLocationX, let hovered = hoveredPoint {
                        let progress = max(0.0, min(1.0, (hovered.timestamp.timeIntervalSince1970 - startTime) / totalDuration))
                        let hx = leftPadding + plotWidth * CGFloat(progress)
                        let hy = topPadding + plotHeight * (1.0 - CGFloat(hovered.percent) / 100.0)

                        // Vertical Hairline
                        Rectangle()
                            .fill(DashboardTheme.infoAccent.opacity(0.65))
                            .frame(width: 1, height: plotHeight)
                            .position(x: hx, y: topPadding + plotHeight / 2)

                        // Point highlight circle
                        Circle()
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(DashboardTheme.batteryGreen, lineWidth: 2))
                            .position(x: hx, y: hy)

                        // Tooltip Box
                        let tooltipWidth: CGFloat = 150
                        let tooltipX = min(width - tooltipWidth - 8, max(leftPadding + 8, hx - tooltipWidth / 2))
                        let tooltipY = max(topPadding + 20, hy - 32)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(Self.formatTimestamp(hovered.timestamp))
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(DashboardTheme.textMuted)
                                Spacer()
                                Text("\(hovered.percent)%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(DashboardTheme.batteryGreen)
                            }

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Self.modeColor(hovered.mode))
                                    .frame(width: 5, height: 5)
                                Text(hovered.mode.title)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(DashboardTheme.textPrimary)
                                Spacer()
                                if abs(hovered.watts) > 0.1 {
                                    Text(String(format: "%+.1f W", hovered.watts))
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .foregroundColor(hovered.watts > 0 ? DashboardTheme.batteryGreen : DashboardTheme.hardwareCoral)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(width: tooltipWidth)
                        .background(DashboardTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                        .position(x: tooltipX + tooltipWidth / 2, y: tooltipY)
                    }
                }

                // X-Axis Time Labels
                HStack {
                    ForEach(timeTickLabels, id: \.0) { tick in
                        if tick.0 == 0.0 {
                            Text(tick.1).font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(DashboardTheme.textMuted)
                            Spacer()
                        } else if tick.0 == 1.0 {
                            Text(tick.1).font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(DashboardTheme.textMuted)
                        } else {
                            Text(tick.1).font(.system(size: 9.5, weight: .medium, design: .monospaced)).foregroundColor(DashboardTheme.textMuted)
                            Spacer()
                        }
                    }
                }
                .padding(.leading, leftPadding)
                .padding(.trailing, rightPadding)
                .frame(width: width)
                .position(x: width / 2, y: height - bottomPadding / 2)
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    hoverLocationX = location.x
                    updateHoveredPoint(location: location, plotWidth: plotWidth, leftPadding: leftPadding)
                case .ended:
                    hoveredPoint = nil
                    hoverLocationX = nil
                }
            }
        }
    }

    private func updateHoveredPoint(location: CGPoint, plotWidth: CGFloat, leftPadding: CGFloat) {
        guard !points.isEmpty, plotWidth > 0 else { return }
        let relX = max(0, min(plotWidth, location.x - leftPadding))
        let progress = Double(relX / plotWidth)
        let now = Date()
        let targetTime = now.addingTimeInterval(-range.duration * (1.0 - progress)).timeIntervalSince1970

        var closest = points[0]
        var minDiff = abs(points[0].timestamp.timeIntervalSince1970 - targetTime)
        for pt in points.dropFirst() {
            let diff = abs(pt.timestamp.timeIntervalSince1970 - targetTime)
            if diff < minDiff {
                minDiff = diff
                closest = pt
            }
        }
        hoveredPoint = closest
    }

    private static func modeColor(_ mode: BatteryPowerMode) -> Color {
        switch mode {
        case .charging: return DashboardTheme.batteryGreen
        case .acPassthrough: return DashboardTheme.infoAccent
        case .discharging: return DashboardTheme.hardwareCoral
        }
    }

    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm • dd/MM"
        return formatter.string(from: date)
    }
}

private struct BatteryHistoryDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
