import CoreGraphics
import Foundation

/// The small ring that shows where a click was: it starts at the click and grows and fades out. Pure: where and how big the
/// rings are at a moment, in pixels of the video; the renderer draws them after the camera has moved.
nonisolated struct ClickEffect: Equatable, Sendable {
    /// How long a ring lasts.
    static let duration = 0.5

    nonisolated struct Ring: Equatable, Sendable {
        var x: Double
        var y: Double
        /// In pixels of the video.
        var radius: Double
        /// 1 at the click, 0 when the ring is gone.
        var opacity: Double
    }

    private let clicks: [ActivityTrack.Click]
    private let startRadius: Double
    private let endRadius: Double

    /// The rings are sized by the video's shorter side, so a 5K recording and a 720p one look alike when shown whole.
    init(clicks: [ActivityTrack.Click], frameSize: CGSize) {
        self.clicks = clicks.sorted { $0.t < $1.t }
        let side = Double(min(frameSize.width, frameSize.height))
        startRadius = side * 0.014
        endRadius = side * 0.04
    }

    /// The rings showing at `time` (recording time). Clicks before `start` are left out: when the video was cut, `start` is
    /// where what is playing began, and a ring from a click that is not in the video would hang there with no cause.
    func rings(at time: TimeInterval, notBefore start: TimeInterval = 0) -> [Ring] {
        let earliest = max(start, time - Self.duration)
        var low = 0, high = clicks.count
        while low < high {
            let middle = (low + high) / 2
            if clicks[middle].t < earliest { low = middle + 1 } else { high = middle }
        }
        var rings: [Ring] = []
        var index = low
        while index < clicks.count, clicks[index].t <= time {
            let click = clicks[index]
            let progress = min(max((time - click.t) / Self.duration, 0), 1)
            if progress < 1 {
                let eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
                rings.append(Ring(
                    x: click.x, y: click.y, radius: startRadius + (endRadius - startRadius) * eased,
                    opacity: 1 - progress * progress
                ))
            }
            index += 1
        }
        return rings
    }
}
