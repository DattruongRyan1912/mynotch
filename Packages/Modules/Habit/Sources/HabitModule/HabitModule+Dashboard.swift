import Foundation
import MyNotchCore

extension HabitModule: DashboardReporting {
    public func dashboardSnapshot() -> DashboardSnapshot {
        let habits = state.habits
        let progress = state.progress
        let today = state.today

        var maxStreak = 0
        for habit in habits {
            let streak = habit.streak(on: today)
            if streak > maxStreak {
                maxStreak = streak
            }
        }

        let metrics: [DashboardMetric] = [
            DashboardMetric(
                name: "Tiến độ hôm nay",
                value: .progress(current: Double(progress.done), total: Double(progress.total), label: "\(progress.done)/\(progress.total)"),
                systemImage: "checkmark.circle"
            ),
            DashboardMetric(
                name: "Chuỗi streak cao nhất",
                value: .number(Double(maxStreak), unit: "ngày"),
                systemImage: "flame.fill"
            ),
            DashboardMetric(
                name: "Tổng số thói quen",
                value: .count(habits.count),
                systemImage: "list.bullet"
            )
        ]

        let status: DashboardStatusLevel = (progress.total > 0 && progress.done == progress.total) ? .success : .normal
        let summary: String
        if habits.isEmpty {
            summary = "Chưa có thói quen nào được tạo"
        } else if progress.done == progress.total {
            summary = "Hoàn thành \(progress.total)/\(progress.total) thói quen hôm nay • Chuỗi \(maxStreak) ngày"
        } else {
            summary = "Đã hoàn thành \(progress.done)/\(progress.total) • Chuỗi dài nhất: \(maxStreak) ngày"
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
