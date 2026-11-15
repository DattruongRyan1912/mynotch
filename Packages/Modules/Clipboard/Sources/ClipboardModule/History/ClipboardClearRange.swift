import Foundation

/// The "Xoá lịch sử…" choices: items copied before the cutoff are removed, pinned ones kept.
nonisolated enum ClipboardClearRange: CaseIterable, Sendable {
    case olderThanOneDay, olderThanOneWeek, olderThanOneMonth, olderThanThreeMonths, all

    var title: String {
        switch self {
        case .olderThanOneDay: "Cũ hơn 24 giờ"
        case .olderThanOneWeek: "Cũ hơn 7 ngày"
        case .olderThanOneMonth: "Cũ hơn 30 ngày"
        case .olderThanThreeMonths: "Cũ hơn 3 tháng"
        case .all: "Tất cả"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .all: "Xoá tất cả lịch sử?"
        default: "Xoá lịch sử \(title.lowercased())?"
        }
    }

    /// Items copied before this date are cleared; nil clears everything unpinned.
    func cutoff(from now: Date) -> Date? {
        let day: TimeInterval = 24 * 60 * 60
        return switch self {
        case .olderThanOneDay: now.addingTimeInterval(-1 * day)
        case .olderThanOneWeek: now.addingTimeInterval(-7 * day)
        case .olderThanOneMonth: now.addingTimeInterval(-30 * day)
        case .olderThanThreeMonths: now.addingTimeInterval(-90 * day)
        case .all: nil
        }
    }
}
