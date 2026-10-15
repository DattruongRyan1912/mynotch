import Foundation
import SwiftUI

/// The lyric views' timeline in karaoke mode: it ticks when the position reaches a line, so a line changes on time and the
/// views are evaluated once per line, not four times a second. The fill within a line is not the timeline's business: that is
/// one animation the render server runs.
nonisolated struct LyricTickSchedule: TimelineSchedule, Sendable {
    /// A tick lands this long after the line begins, so the position computed from the date is past the line, never a hair
    /// before it.
    static let settle = 0.005

    var anchor: PlaybackAnchor?
    var isPlaying: Bool
    /// The lines' times, in order.
    var lineTimes: [Double]

    /// `startDate`, then each moment the position reaches a later line; only `startDate` while the position stands still (the
    /// view builds a new schedule when the store's anchor changes).
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        guard isPlaying, let anchor, anchor.rate > 0 else { return Entries(start: startDate, anchor: nil, times: [], index: 0) }
        let position = anchor.elapsedSeconds + startDate.timeIntervalSince(anchor.timestamp) * anchor.rate
        // The first line that begins after the position, found by binary search.
        var low = 0
        var high = lineTimes.count
        while low < high {
            let middle = (low + high) / 2
            if lineTimes[middle] <= position { low = middle + 1 } else { high = middle }
        }
        return Entries(start: startDate, anchor: anchor, times: lineTimes, index: low)
    }

    nonisolated struct Entries: Sequence, IteratorProtocol, Sendable {
        fileprivate var start: Date?
        fileprivate let anchor: PlaybackAnchor?
        fileprivate let times: [Double]
        fileprivate var index: Int

        mutating func next() -> Date? {
            if let start {
                self.start = nil
                return start
            }
            guard let anchor, index < times.count else { return nil }
            defer { index += 1 }
            // Computed from the anchor each time, so no error builds up.
            return anchor.timestamp + (times[index] - anchor.elapsedSeconds) / anchor.rate + LyricTickSchedule.settle
        }
    }
}
