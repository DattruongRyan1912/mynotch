import Foundation
import MyNotchCore

extension BatteryModule: DashboardReporting {
    public func dashboardSnapshot() -> DashboardSnapshot {
        guard let snapshot = state.snapshot else {
            return DashboardSnapshot(
                moduleID: descriptor.id,
                title: descriptor.displayName,
                systemImage: descriptor.systemImage,
                status: .normal,
                summary: "Không có dữ liệu pin",
                metrics: [
                    DashboardMetric(name: "Trạng thái", value: .text("Không có pin hoặc đang đọc"), systemImage: "battery.slash")
                ]
            )
        }

        let percent = snapshot.percent
        let isOnAC = snapshot.isOnAC
        let isCharging = snapshot.isCharging
        let health = state.details?.healthPercent
        let cycles = state.details?.cycleCount
        let watts = state.details?.batteryWatts
        let temp = state.details?.temperatureCelsius

        var metrics: [DashboardMetric] = [
            DashboardMetric(name: "Dung lượng pin", value: .number(Double(percent), unit: "%"), systemImage: "battery.100percent"),
            DashboardMetric(name: "Nguồn điện", value: .text(isOnAC ? (isCharging ? "Đang sạc (AC)" : "Nguồn ngoài (AC)") : "Dùng pin"), systemImage: isOnAC ? "bolt.fill" : "battery.50percent")
        ]

        if let health {
            metrics.append(DashboardMetric(name: "Độ chai pin", value: .number(Double(health), unit: "%"), systemImage: "heart.fill"))
        }
        if let cycles {
            metrics.append(DashboardMetric(name: "Chu kỳ sạc", value: .count(cycles), systemImage: "arrow.triangle.2.circlepath"))
        }
        if let watts {
            metrics.append(DashboardMetric(name: "Công suất", value: .number(abs(watts), unit: "W"), systemImage: "bolt.badge.automatic"))
        }
        if let temp {
            metrics.append(DashboardMetric(name: "Nhiệt độ pin", value: .number(temp, unit: "°C"), systemImage: "thermometer.medium"))
        }

        if state.isLimitToEightyEnabled {
            metrics.append(DashboardMetric(name: "Khóa sạc 80%", value: .text("Bật (AlDente Mode)"), systemImage: "shield.fill"))
        }

        let status: DashboardStatusLevel
        if percent <= 15 && !isOnAC {
            status = .critical
        } else if percent <= 25 && !isOnAC {
            status = .warning
        } else if isCharging || (isOnAC && percent >= 80) {
            status = .success
        } else {
            status = .normal
        }

        let powerDesc = isOnAC ? (isCharging ? "Đang sạc" : "Nguồn AC") : "Pin"
        let summaryParts: [String] = [
            "\(percent)%",
            powerDesc,
            watts.map { String(format: "%.1fW", abs($0)) },
            health.map { "Sức khỏe \($0)%" }
        ].compactMap { $0 }

        let summary = summaryParts.joined(separator: " • ")

        return DashboardSnapshot(
            moduleID: descriptor.id,
            title: descriptor.displayName,
            systemImage: descriptor.systemImage,
            status: status,
            summary: summary,
            metrics: metrics
        )
    }
}
