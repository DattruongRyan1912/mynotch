import Foundation
import MyNotchCore

extension PerformanceModule: DashboardReporting {
    public func setDashboardActive(_ active: Bool) {
        guard isDashboardActive != active else { return }
        isDashboardActive = active
        updatePolling()
    }

    public func dashboardSnapshot() -> DashboardSnapshot {
        var metrics: [DashboardMetric] = []
        let cpuTemp = state.thermal?.cpu
        let gpuTemp = state.thermal?.gpu
        let cpu = state.cpuUsage
        let mem = state.usage

        if let cpuTemp {
            metrics.append(DashboardMetric(name: "CPU Nhiệt độ", value: .number(cpuTemp, unit: "°C"), systemImage: "flame.fill"))
        }
        if let gpuTemp {
            metrics.append(DashboardMetric(name: "GPU Nhiệt độ", value: .number(gpuTemp, unit: "°C"), systemImage: "flame"))
        }
        if let cpu {
            metrics.append(DashboardMetric(name: "CPU Usage", value: .number(cpu, unit: "%"), systemImage: "cpu"))
        }
        if let mem {
            let usedGB = Double(mem.used) / 1_000_000_000.0
            let totalGB = Double(mem.total) / 1_000_000_000.0
            metrics.append(DashboardMetric(name: "RAM", value: .text(String(format: "%.1f / %.1f GB", usedGB, totalGB)), systemImage: "memorychip"))
            metrics.append(DashboardMetric(name: "Tỷ lệ sử dụng RAM", value: .number(mem.fraction * 100.0, unit: "%"), systemImage: "gauge.medium"))
        }
        if let fans = state.thermal?.fans, !fans.isEmpty {
            let fanSpeeds = fans.map { "\(Int($0.rpm)) RPM" }.joined(separator: ", ")
            metrics.append(DashboardMetric(name: "Quạt làm mát", value: .text(fanSpeeds), systemImage: "fanblades"))
        }

        let summaryParts: [String] = [
            cpuTemp.map { String(format: "CPU %.0f°C", $0) },
            cpu.map { String(format: "%.0f%%", $0) },
            mem.map { "\(Int($0.fraction * 100.0))% RAM" }
        ].compactMap { $0 }

        let summary = summaryParts.isEmpty ? "Đang đọc số liệu..." : summaryParts.joined(separator: " • ")
        let status: DashboardStatusLevel = (cpuTemp ?? 0) > 85 ? .warning : .normal

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
