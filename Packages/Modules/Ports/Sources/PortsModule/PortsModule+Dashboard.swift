import Foundation
import MyNotchCore

extension PortsModule: DashboardReporting {
    public func dashboardSnapshot() -> DashboardSnapshot {
        let count = state.entries.count
        let tcpCount = state.entries.filter { $0.proto == .tcp }.count
        let udpCount = state.entries.filter { $0.proto == .udp }.count

        let metrics: [DashboardMetric] = [
            DashboardMetric(name: "Tổng cổng lắng nghe", value: .count(count), systemImage: "network"),
            DashboardMetric(name: "Cổng TCP", value: .count(tcpCount), systemImage: "arrow.up.right.and.arrow.down.left.rectangle"),
            DashboardMetric(name: "Cổng UDP", value: .count(udpCount), systemImage: "antenna.radiowaves.left.and.right")
        ]

        let summary = count > 0 ? "\(count) cổng đang mở (\(tcpCount) TCP, \(udpCount) UDP)" : "Không có cổng nào đang mở"

        return DashboardSnapshot(
            moduleID: descriptor.id,
            title: descriptor.displayName,
            systemImage: descriptor.systemImage,
            status: .normal,
            summary: summary,
            metrics: metrics
        )
    }
}
