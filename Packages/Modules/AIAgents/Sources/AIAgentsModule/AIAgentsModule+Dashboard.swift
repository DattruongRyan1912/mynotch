import Foundation
import MyNotchCore

extension AIAgentsModule: DashboardReporting {
    public func dashboardSnapshot() -> DashboardSnapshot {
        let activeSessions = store?.sessions.values.filter { $0.state != .idle } ?? []
        let totalSessions = store?.sessions.count ?? 0

        var metrics: [DashboardMetric] = [
            DashboardMetric(name: "Phiên AI hoạt động", value: .count(activeSessions.count), systemImage: "terminal.fill"),
            DashboardMetric(name: "Tổng số phiên", value: .count(totalSessions), systemImage: "list.bullet.rectangle")
        ]

        let status: DashboardStatusLevel = !activeSessions.isEmpty ? .success : .normal
        let summary: String
        if !activeSessions.isEmpty {
            summary = "\(activeSessions.count) phiên đang xử lý tác vụ"
        } else if totalSessions > 0 {
            summary = "\(totalSessions) phiên đang ở trạng thái rảnh"
        } else {
            summary = "Chưa có phiên AI nào"
        }

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
