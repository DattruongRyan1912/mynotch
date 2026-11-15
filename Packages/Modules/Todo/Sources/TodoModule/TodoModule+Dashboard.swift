import Foundation
import MyNotchCore

extension TodoModule: DashboardReporting {
    public func dashboardSnapshot() -> DashboardSnapshot {
        let progress = state.progress
        let matrix = state.matrix

        let q1Count = matrix[.doFirst]?.count ?? 0
        let q2Count = matrix[.schedule]?.count ?? 0
        let q3Count = matrix[.delegate]?.count ?? 0
        let q4Count = matrix[.eliminate]?.count ?? 0

        let metrics: [DashboardMetric] = [
            DashboardMetric(name: "Tiến độ hôm nay", value: .progress(current: Double(progress.done), total: Double(progress.total), label: "\(progress.done)/\(progress.total)")),
            DashboardMetric(name: "Q1 Khẩn cấp & Quan trọng", value: .count(q1Count), systemImage: "exclamationmark.circle.fill"),
            DashboardMetric(name: "Q2 Lên lịch", value: .count(q2Count), systemImage: "calendar.badge.clock"),
            DashboardMetric(name: "Q3 Uỷ quyền", value: .count(q3Count), systemImage: "person.2.fill"),
            DashboardMetric(name: "Q4 Xoá bỏ", value: .count(q4Count), systemImage: "arrow.down.circle")
        ]

        let isAllDone = progress.total > 0 && progress.done == progress.total
        let status: DashboardStatusLevel = q1Count > 0 ? .warning : (isAllDone ? .success : .normal)
        let summary: String
        if progress.total == 0 {
            summary = "Không có việc cần làm hôm nay"
        } else if isAllDone {
            summary = "Đã hoàn thành toàn bộ \(progress.total) việc"
        } else {
            summary = "\(progress.done)/\(progress.total) việc đã xong • \(q1Count) việc Q1 cần ưu tiên"
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
