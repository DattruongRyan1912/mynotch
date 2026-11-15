import Foundation
import MyNotchCore

extension CalendarModule: DashboardReporting {
    public func dashboardSnapshot() -> DashboardSnapshot {
        let events = state.agenda.today
        let featured = state.featured ?? state.agenda.next

        var metrics: [DashboardMetric] = [
            DashboardMetric(name: "Sự kiện hôm nay", value: .count(events.count), systemImage: "calendar")
        ]

        if let featured {
            metrics.append(DashboardMetric(name: "Sắp tới", value: .text(featured.title), systemImage: "clock.fill"))
        }

        let summary: String
        if let featured {
            summary = "Sắp tới: \(featured.title) • \(events.count) sự kiện hôm nay"
        } else if events.isEmpty {
            summary = "Không có sự kiện nào hôm nay"
        } else {
            summary = "\(events.count) sự kiện trong ngày"
        }

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
