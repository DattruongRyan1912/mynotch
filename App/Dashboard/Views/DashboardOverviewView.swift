import MyNotchCore
import SwiftUI

struct DashboardOverviewView: View {
    let telemetry: DashboardTelemetryCenter
    let onNavigateToTab: (DashboardTab) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top KPI Grid (4 columns)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    // 1. CPU & SoC
                    cpuMetricCard

                    // 2. Battery & Power
                    batteryMetricCard

                    // 3. Memory RAM
                    memoryMetricCard

                    // 4. Todo Progress
                    todoMetricCard

                    // 5. Habits Streak
                    habitMetricCard

                    // 6. Media Playing
                    mediaMetricCard

                    // 7. Network Ports
                    portsMetricCard

                    // 8. Cleaner Storage
                    cleanerMetricCard
                }

                // Middle Split: Eisenhower Matrix & Upcoming Agenda
                HStack(alignment: .top, spacing: 16) {
                    // Left: Eisenhower Matrix Breakdown
                    eisenhowerCard
                        .frame(maxWidth: .infinity)

                    // Right: Upcoming Agenda & Workspace Telemetry
                    VStack(spacing: 16) {
                        calendarCard
                        agentsCard
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
    }

    // MARK: - KPI Cards

    private var cpuMetricCard: some View {
        let snap = telemetry.performanceSnapshot
        let tempMetric = snap?.metric(named: "CPU")
        let fanMetric = snap?.metric(named: "Quạt")

        return DashboardMetricCard(
            label: "Nhiệt độ SoC",
            value: tempMetric?.value.displayString ?? "--",
            unit: tempMetric?.value.unitString ?? "°C",
            icon: "cpu",
            level: snap?.status ?? .normal,
            subtitle: fanMetric.map { "Quạt: \($0.value.displayString)" } ?? "Quạt tĩnh lặng"
        )
    }

    private var batteryMetricCard: some View {
        let snap = telemetry.batterySnapshot
        let pctMetric = snap?.metric(named: "Dung lượng")
        let powerSource = snap?.metric(named: "Nguồn")?.value.displayString ?? "Pin"
        let wattsMetric = snap?.metric(named: "Công suất")

        var subtitle = powerSource
        if let w = wattsMetric, let wVal = w.value.numberValue, abs(wVal) > 0.05 {
            subtitle += " • \(String(format: "%.1fW", wVal))"
        }

        return Button {
            onNavigateToTab(.battery)
        } label: {
            DashboardMetricCard(
                label: "Pin & Nguồn",
                value: pctMetric?.value.displayString ?? "--",
                unit: pctMetric?.value.unitString ?? "%",
                icon: "battery.100percent.bolt",
                iconColor: DashboardTheme.batteryGreen,
                level: snap?.status ?? .normal,
                subtitle: subtitle
            )
        }
        .buttonStyle(.plain)
    }

    private var memoryMetricCard: some View {
        let snap = telemetry.performanceSnapshot
        let memMetric = snap?.metric(named: "RAM")
        let fractionMetric = snap?.metric(named: "Tỷ lệ")

        var sub = "Hệ thống"
        if let frac = fractionMetric?.value.numberValue {
            sub = "Tỷ lệ sử dụng: \(Int(frac))%"
        }

        return DashboardMetricCard(
            label: "Bộ nhớ RAM",
            value: memMetric?.value.displayString ?? "--",
            unit: "",
            icon: "memorychip",
            level: snap?.status ?? .normal,
            subtitle: sub
        )
    }

    private var todoMetricCard: some View {
        let snap = telemetry.todoSnapshot
        let progressMetric = snap?.metric(named: "Tiến độ")
        let q1Metric = snap?.metric(named: "Q1")

        let q1Count = q1Metric?.value.numberValue.map { Int($0) } ?? 0

        return Button {
            onNavigateToTab(.todo)
        } label: {
            DashboardMetricCard(
                label: "Việc cần làm",
                value: progressMetric?.value.displayString ?? "0/0",
                unit: "việc",
                icon: "checklist",
                iconColor: DashboardTheme.todoBlue,
                level: q1Count > 0 ? .warning : (snap?.status ?? .normal),
                subtitle: q1Count > 0 ? "⚠️ \(q1Count) việc Q1 khẩn cấp" : "Đã kiểm soát tốt"
            )
        }
        .buttonStyle(.plain)
    }

    private var habitMetricCard: some View {
        let snap = telemetry.habitSnapshot
        let streakMetric = snap?.metric(named: "streak")
        let progressMetric = snap?.metric(named: "Tiến độ")

        let sub = "Hôm nay: \(progressMetric?.value.displayString ?? "0/0") xong"

        return DashboardMetricCard(
            label: "Thói quen",
            value: streakMetric?.value.displayString ?? "0",
            unit: "ngày streak",
            icon: "flame",
            level: snap?.status ?? .normal,
            subtitle: sub
        )
    }

    private var mediaMetricCard: some View {
        let snap = telemetry.mediaSnapshot
        let statusMetric = snap?.metric(named: "Trạng thái")
        let isPlaying = statusMetric?.value.displayString.contains("Đang phát") ?? false
        let title = snap?.metric(named: "Tên bài")?.value.displayString ?? "Đang tạm dừng"
        let artist = snap?.metric(named: "Nghệ sĩ")?.value.displayString ?? "Không có bài hát"

        return Button {
            onNavigateToTab(.audio)
        } label: {
            DashboardMetricCard(
                label: "Âm thanh & EQ",
                value: isPlaying ? "Đang phát" : "Tạm dừng",
                icon: "slider.vertical.3",
                level: isPlaying ? .success : .normal,
                subtitle: isPlaying ? "\(title) — \(artist)" : artist
            )
        }
        .buttonStyle(.plain)
    }

    private var portsMetricCard: some View {
        let snap = telemetry.portsSnapshot
        let totalMetric = snap?.metric(named: "Tổng")
        let tcpMetric = snap?.metric(named: "TCP")
        let udpMetric = snap?.metric(named: "UDP")

        let sub = "TCP: \(tcpMetric?.value.displayString ?? "0") • UDP: \(udpMetric?.value.displayString ?? "0")"

        return DashboardMetricCard(
            label: "Cổng mạng mở",
            value: totalMetric?.value.displayString ?? "0",
            unit: "cổng",
            icon: "network",
            level: snap?.status ?? .normal,
            subtitle: sub
        )
    }

    private var cleanerMetricCard: some View {
        let snap = telemetry.cleanerSnapshot
        let freedMetric = snap?.metric(named: "gỡ")

        return Button {
            onNavigateToTab(.cleaner)
        } label: {
            DashboardMetricCard(
                label: "Dọn dẹp & Tối ưu",
                value: "Sẵn sàng",
                unit: "",
                icon: "trash",
                level: snap?.status ?? .normal,
                subtitle: freedMetric?.value.displayString ?? "Dọn rác & bộ nhớ"
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Eisenhower Matrix Card

    private var eisenhowerCard: some View {
        let snap = telemetry.todoSnapshot
        let q1 = Int(snap?.metric(named: "Q1")?.value.numberValue ?? 0)
        let q2 = Int(snap?.metric(named: "Q2")?.value.numberValue ?? 0)
        let q3 = Int(snap?.metric(named: "Q3")?.value.numberValue ?? 0)
        let q4 = Int(snap?.metric(named: "Q4")?.value.numberValue ?? 0)
        let total = q1 + q2 + q3 + q4

        return VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Ma trận Eisenhower",
                subtitle: "\(total) công việc phân loại",
                actionTitle: "Xem Todo Studio →"
            ) {
                onNavigateToTab(.todo)
            }

            VStack(spacing: 8) {
                eisenhowerRow(
                    label: "Q1 • Làm ngay (Khẩn cấp & Quan trọng)",
                    count: q1,
                    total: total,
                    color: DashboardTheme.statusCritical
                )
                eisenhowerRow(
                    label: "Q2 • Lên lịch (Quan trọng, không khẩn)",
                    count: q2,
                    total: total,
                    color: DashboardTheme.infoAccent
                )
                eisenhowerRow(
                    label: "Q3 • Uỷ thác (Khẩn, không quan trọng)",
                    count: q3,
                    total: total,
                    color: DashboardTheme.statusDegraded
                )
                eisenhowerRow(
                    label: "Q4 • Xoá bỏ (Không khẩn, không quan trọng)",
                    count: q4,
                    total: total,
                    color: DashboardTheme.statusNeutral
                )
            }
        }
        .dashboardCard()
    }

    private func eisenhowerRow(label: String, count: Int, total: Int, color: Color) -> some View {
        let fraction = total > 0 ? Double(count) / Double(total) : 0.0

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardTheme.textSecondary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(DashboardTheme.textPrimary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DashboardTheme.subtleDivider)
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: max(0, min(proxy.size.width, proxy.size.width * CGFloat(fraction))), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Calendar Card

    private var calendarCard: some View {
        let snap = telemetry.calendarSnapshot
        let todayCount = Int(snap?.metric(named: "Sự kiện")?.value.numberValue ?? 0)
        let nextTitle = snap?.metric(named: "Sắp tới")?.value.displayString

        return VStack(alignment: .leading, spacing: 10) {
            DashboardSectionHeader(
                title: "Lịch & Sự kiện",
                subtitle: "\(todayCount) sự kiện hôm nay",
                actionTitle: "Chi tiết →"
            ) {
                onNavigateToTab(.productivity)
            }

            if let nextTitle, !nextTitle.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SỰ KIỆN KẾ TIẾP")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(DashboardTheme.textMuted)

                    Text(nextTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DashboardTheme.textPrimary)
                        .lineLimit(1)
                }
                .padding(10)
                .background(DashboardTheme.insetBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(DashboardTheme.insetBorder, lineWidth: 1)
                )
            } else {
                Text("Không có sự kiện sắp tới trong hôm nay.")
                    .font(.system(size: 12))
                    .foregroundColor(DashboardTheme.textMuted)
                    .padding(.vertical, 4)
            }
        }
        .dashboardCard()
    }

    // MARK: - AI Agents Card

    private var agentsCard: some View {
        let snap = telemetry.agentsSnapshot
        let active = Int(snap?.metric(named: "hoạt động")?.value.numberValue ?? 0)
        let total = Int(snap?.metric(named: "Tổng")?.value.numberValue ?? 0)

        return VStack(alignment: .leading, spacing: 10) {
            DashboardSectionHeader(
                title: "Trợ lý AI Agents",
                subtitle: "\(total) phiên",
                actionTitle: "Quản lý →"
            ) {
                onNavigateToTab(.modules)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trạng thái xử lý")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(DashboardTheme.textMuted)
                    Text(active > 0 ? "\(active) phiên đang chạy" : "Tất cả phiên đang rảnh")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DashboardTheme.textPrimary)
                }
                Spacer()
                DashboardBadge(text: active > 0 ? "Bận" : "Sẵn sàng", level: active > 0 ? .warning : .success)
            }
        }
        .dashboardCard()
    }
}
