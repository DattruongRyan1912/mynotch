import Foundation
import SwiftUI

/// Ticks when the playback position reaches each whole second, so the elapsed time changes in step with
/// the player instead of at the arbitrary phase of a fixed 1 s timer (up to a second late, and drifting).
nonisolated struct PlaybackTickSchedule: TimelineSchedule, Sendable {
    var anchor: PlaybackAnchor?
    var isPlaying: Bool

    /// `startDate`, then each moment the position reaches a whole second; only `startDate` while the position
    /// stands still (the view redraws when the store changes).
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        guard isPlaying, let anchor, anchor.rate > 0 else { return Entries(start: startDate, anchor: nil, second: 0) }
        let position = anchor.elapsedSeconds + startDate.timeIntervalSince(anchor.timestamp) * anchor.rate
        // At least the tolerance ahead, so a start right on a whole second does not tick twice.
        let next = (position + PlaybackProgress.secondTolerance).rounded(.down) + 1
        return Entries(start: startDate, anchor: anchor, second: next)
    }

    nonisolated struct Entries: Sequence, IteratorProtocol, Sendable {
        fileprivate var start: Date?
        fileprivate let anchor: PlaybackAnchor?
        /// The whole position second of the next tick; each date is computed from the anchor, so none accumulates error.
        fileprivate var second: Double

        mutating func next() -> Date? {
            if let start {
                self.start = nil
                return start
            }
            guard let anchor else { return nil }
            defer { second += 1 }
            return anchor.timestamp + (second - anchor.elapsedSeconds) / anchor.rate
        }
    }
}
