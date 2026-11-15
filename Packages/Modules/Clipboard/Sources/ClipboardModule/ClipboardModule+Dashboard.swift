import Foundation
import MyNotchCore

extension ClipboardModule: DashboardReporting {
    public func dashboardSnapshot() -> DashboardSnapshot {
        let totalItems = state.history.items.count
        let pinsCount = Set(state.history.boards.flatMap(\.itemIDs)).count
        let boardsCount = state.history.boards.count

        let metrics: [DashboardMetric] = [
            DashboardMetric(name: "Lịch sử clipboard", value: .count(totalItems), systemImage: "doc.on.clipboard"),
            DashboardMetric(name: "Mục đã ghim", value: .count(pinsCount), systemImage: "pin.fill"),
            DashboardMetric(name: "Số lượng board", value: .count(boardsCount), systemImage: "square.grid.2x2")
        ]

        let summary = totalItems > 0 ? "\(totalItems) mục đã lưu • \(pinsCount) mục ghim • \(boardsCount) boards" : "Chưa có lịch sử sao chép"

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
