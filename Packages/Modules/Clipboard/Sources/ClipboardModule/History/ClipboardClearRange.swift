import Foundation

/// The "Xoá lịch sử…" choices: items copied within the range are removed, pinned ones kept.
nonisolated enum ClipboardClearRange: CaseIterable, Sendable {
    case lastFifteenMinutes, lastHour, lastDay, lastWeek, all

    var title: String {
        switch self {
        case .lastFifteenMinutes: "15 phút qua"
        case .lastHour: "1 giờ qua"
        case .lastDay: "1 ngày qua"
        case .lastWeek: "1 tuần qua"
        case .all: "Tất cả"
        }
    }

    /// Items copied after this date are cleared; nil clears everything.
    func cutoff(from now: Date) -> Date? {
        let minute: TimeInterval = 60
        return switch self {
        case .lastFifteenMinutes: now.addingTimeInterval(-15 * minute)
        case .lastHour: now.addingTimeInterval(-60 * minute)
        case .lastDay: now.addingTimeInterval(-24 * 60 * minute)
        case .lastWeek: now.addingTimeInterval(-7 * 24 * 60 * minute)
        case .all: nil
        }
    }
}
