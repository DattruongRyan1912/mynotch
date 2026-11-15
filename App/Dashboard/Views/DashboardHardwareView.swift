import MyNotchCore
import SwiftUI

struct DashboardHardwareView: View {
    let telemetry: DashboardTelemetryCenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: SoC & Thermal Management
                thermalSection

                // Section 2: Memory Allocation
                memorySection

                // Section 3: Battery & Power Delivery
                batterySection

                // Section 4: Network Listening Ports
                portsSection
            }
            .padding(20)
        }
    }

    // MARK: - Thermal Section

    private var thermalSection: some View {
        let snap = telemetry.performanceSnapshot
        let cpuTemp = snap?.metric(named: "CPU")
        let gpuTemp = snap?.metric(named: "GPU")
        let fanRPM = snap?.metric(named: "Quạt")

        return VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Nhiệt độ & Tản nhiệt SoC",
                subtitle: "Apple Silicon Apple SMC Sensors"
            )

            HStack(spacing: 12) {
                DashboardMetricCard(
                    label: "Nhiệt độ CPU",
                    value: cpuTemp?.value.displayString ?? "--",
                    unit: cpuTemp?.value.unitString ?? "°C",
                    icon: "thermometer.medium",
                    level: snap?.status ?? .normal
                )

                DashboardMetricCard(
                    label: "Nhiệt độ GPU",
                    value: gpuTemp?.value.displayString ?? "--",
                    unit: gpuTemp?.value.unitString ?? "°C",
                    icon: "sparkles.tv",
                    level: snap?.status ?? .normal
                )

                DashboardMetricCard(
                    label: "Tốc độ quạt",
                    value: fanRPM?.value.displayString ?? "0 RPM",
                    unit: "",
                    icon: "fanblades",
                    level: .normal,
                    subtitle: (fanRPM != nil) ? "Làm mát chủ động" : "Tĩnh lặng hoàn toàn"
                )
            }
        }
        .dashboardCard()
    }

    // MARK: - Memory Section

    private var memorySection: some View {
        let snap = telemetry.performanceSnapshot
        let ram = snap?.metric(named: "RAM")
        let fraction = snap?.metric(named: "Tỷ lệ")?.value.numberValue ?? 0.0

        return VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Bộ nhớ RAM hệ thống",
                subtitle: "Unified Memory Architecture"
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ÁP LỰC BỘ NHỚ")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DashboardTheme.textMuted)
                        Text("\(Int(fraction))%")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(fraction > 85 ? DashboardTheme.statusCritical : DashboardTheme.textPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("ĐÃ SỬ DỤNG / TỔNG")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DashboardTheme.textMuted)
                        Text(ram?.value.displayString ?? "--")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(DashboardTheme.textSecondary)
                    }
                }

                // Progress Bar
                GeometryReader { proxy in
                    let frac = fraction / 100.0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DashboardTheme.subtleDivider)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(frac > 0.85 ? DashboardTheme.statusCritical : (frac > 0.7 ? DashboardTheme.statusDegraded : DashboardTheme.infoAccent))
                            .frame(width: max(0, min(proxy.size.width, proxy.size.width * CGFloat(frac))), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .dashboardCard()
    }

    // MARK: - Battery Section

    private var batterySection: some View {
        let snap = telemetry.batterySnapshot
        let pct = snap?.metric(named: "Dung lượng")?.value.displayString ?? "--"
        let powerSource = snap?.metric(named: "Nguồn")?.value.displayString ?? "Pin"
        let watts = snap?.metric(named: "Công suất")?.value.numberValue
        let cycles = snap?.metric(named: "Chu kỳ")?.value.displayString ?? "--"
        let health = snap?.metric(named: "Độ chai")?.value.displayString ?? "--"
        let alDenteHeld = snap?.metric(named: "Khóa sạc") != nil

        return VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Nguồn điện & Quản lý Pin",
                subtitle: "IOPlatformPower & SMC Driver"
            )

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                DashboardMetricCard(
                    label: "Dung lượng pin",
                    value: pct,
                    unit: "%",
                    icon: "battery.100percent",
                    level: snap?.status ?? .normal,
                    subtitle: powerSource
                )

                DashboardMetricCard(
                    label: "Công suất",
                    value: watts.map { String(format: "%.1f", abs($0)) } ?? "0.0",
                    unit: "W",
                    icon: "bolt.fill",
                    level: .normal,
                    subtitle: (watts ?? 0) > 0.1 ? "Đang nạp năng lượng" : "Chạy pin tiêu thụ"
                )

                DashboardMetricCard(
                    label: "Chế độ AlDente",
                    value: alDenteHeld ? "80% Limit" : "Bình thường",
                    unit: "",
                    icon: "shield.lefthalf.filled",
                    level: alDenteHeld ? .success : .normal,
                    subtitle: alDenteHeld ? "Bypass Mode SMC khóa sạc" : "Không giới hạn"
                )
            }

            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Text("Chu kỳ sạc:")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(DashboardTheme.textMuted)
                    Text("\(cycles) cycles")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DashboardTheme.textPrimary)
                }

                HStack(spacing: 6) {
                    Text("Sức khỏe pin:")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(DashboardTheme.textMuted)
                    Text("\(health)%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DashboardTheme.textPrimary)
                }

                Spacer()
            }
            .padding(.top, 4)
        }
        .dashboardCard()
    }

    // MARK: - Ports Section

    private var portsSection: some View {
        let snap = telemetry.portsSnapshot
        let total = snap?.metric(named: "Tổng")?.value.displayString ?? "0"
        let tcp = snap?.metric(named: "TCP")?.value.displayString ?? "0"
        let udp = snap?.metric(named: "UDP")?.value.displayString ?? "0"

        return VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Cổng mạng đang lắng nghe (Open Ports)",
                subtitle: "\(total) cổng (TCP: \(tcp) • UDP: \(udp))"
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GIÁM SÁT KẾT NỐI MẠNG")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(DashboardTheme.textMuted)

                    Text("Hệ thống liên tục theo dõi các tiến trình máy chủ cục bộ (Localhost) đang chiếm dụng cổng mạng.")
                        .font(.system(size: 12))
                        .foregroundColor(DashboardTheme.textSecondary)
                }

                Spacer()

                DashboardBadge(text: "Lắng nghe ngầm", level: .normal)
            }
        }
        .dashboardCard()
    }
}
