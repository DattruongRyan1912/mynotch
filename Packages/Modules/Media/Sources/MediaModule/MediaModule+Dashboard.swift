import Foundation
import MyNotchCore

extension MediaModule: DashboardReporting {
    public func dashboardSnapshot() -> DashboardSnapshot {
        let isPlaying = store.state.isPlaying
        let title = store.state.title
        let artist = store.state.artist
        let app = store.appName

        var metrics: [DashboardMetric] = [
            DashboardMetric(name: "Trạng thái phát", value: .text(isPlaying ? "Đang phát" : "Đang dừng"), systemImage: isPlaying ? "play.circle.fill" : "pause.circle")
        ]

        if let title {
            metrics.append(DashboardMetric(name: "Tên bài", value: .text(title), systemImage: "music.note"))
        }
        if let artist {
            metrics.append(DashboardMetric(name: "Nghệ sĩ", value: .text(artist), systemImage: "person.wave.2"))
        }
        if let app {
            metrics.append(DashboardMetric(name: "Ứng dụng nguồn", value: .text(app), systemImage: "app.connected.to.app.below.fill"))
        }

        let summary: String
        if let title {
            let artistSuffix = artist.map { " - \($0)" } ?? ""
            let statusPrefix = isPlaying ? "▶ " : "⏸ "
            summary = "\(statusPrefix)\(title)\(artistSuffix)"
        } else {
            summary = "Không có âm thanh đang phát"
        }

        return DashboardSnapshot(
            moduleID: descriptor.id,
            title: descriptor.displayName,
            systemImage: descriptor.systemImage,
            status: isPlaying ? .success : .normal,
            summary: summary,
            metrics: metrics
        )
    }
}
