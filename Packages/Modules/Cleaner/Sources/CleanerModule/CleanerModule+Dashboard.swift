import Foundation
import MyNotchCore

extension CleanerModule: DashboardReporting {
    public func dashboardSnapshot() -> DashboardSnapshot {
        var metrics: [DashboardMetric] = [
            DashboardMetric(name: "Trạng thái", value: .text("Sẵn sàng dọn dẹp"), systemImage: "trash")
        ]

        if case .success(let appName, let freedBytes) = state.phase {
            let freedMB = Double(freedBytes) / 1_000_000.0
            metrics.append(DashboardMetric(name: "Đã gỡ gần nhất", value: .text("\(appName) (\(String(format: "%.1f MB", freedMB)))"), systemImage: "trash"))
        }

        let summary = "Gỡ ứng dụng & Dọn dẹp hệ thống an toàn"

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
