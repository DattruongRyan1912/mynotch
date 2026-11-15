import CoreGraphics
import Foundation

/// Where things are on the timeline, which shows the recording from its first moment to its last, left to right, in recording
/// time: a cut stretch is still there, dimmed, so it can be brought back.
nonisolated struct TimelineGeometry: Equatable, Sendable {
    /// Points across the whole recording.
    var width: CGFloat
    var duration: TimeInterval

    /// Where `time` is, kept between the two ends.
    func x(for time: TimeInterval) -> CGFloat {
        guard duration > 0, time.isFinite else { return 0 }
        return CGFloat(min(max(time / duration, 0), 1)) * width
    }

    /// The moment at `x`, kept inside the recording.
    func time(at x: CGFloat) -> TimeInterval {
        guard width > 0, x.isFinite else { return 0 }
        return min(max(Double(x / width), 0), 1) * duration
    }

    /// The span of `range` as a position and a width.
    func span(of range: Range<TimeInterval>) -> (x: CGFloat, width: CGFloat) {
        let start = x(for: range.lowerBound)
        return (start, x(for: range.upperBound) - start)
    }

    /// A mark on the ruler.
    struct Tick: Equatable, Sendable {
        var time: TimeInterval
        var label: String
    }

    /// Marks at a round number of seconds, as many as fit with `minimumSpacing` points between neighbours.
    func rulerTicks(minimumSpacing: CGFloat = 64) -> [Tick] {
        guard duration > 0, width > 0 else { return [] }
        let steps: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1_800, 3_600]
        let step = steps.first { x(for: $0) >= minimumSpacing } ?? steps[steps.count - 1]
        return stride(from: 0, through: duration, by: step).map { Tick(time: $0, label: Self.label(for: $0)) }
    }

    /// "0:05", "12:30", "1:02:03".
    static func label(for time: TimeInterval) -> String {
        let total = Int(max(time, 0).rounded(.down))
        let hours = total / 3_600, minutes = total % 3_600 / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
