import CoreGraphics
import Foundation

/// Where the camera looks at each moment of the recording: the part of the video that fills the frame.
///
/// The camera is three critically damped springs (the middle of the view and its size) that chase a target: the whole picture
/// when no zoom is active, and the focus of the active zoom, at its scale, when one is. A spring never jumps and never
/// overshoots a target it was heading for, so the path is smooth however fast the targets move, and a click that arrives while
/// the picture is still zooming out zooms in again from where it is. Springs cannot be evaluated for one moment alone, so the
/// path is computed once, a hundred and twenty times a second, and `rect(at:)` reads it: seeking, playing and exporting get
/// the same rectangle for the same moment.
///
/// All three springs share a rate, so the view's four edges move together along straight lines: a point inside the view at the
/// start of a zoom and inside it at the end stays inside all the way.
nonisolated struct CameraPath: Sendable {
    /// Seconds between the computed points; the camera is smooth enough between them for a straight line to do.
    static let step = 1.0 / 120
    /// A spring covers about 96% of the way in the time asked for: `1 - (1 + 5) * e^-5`.
    static let rate = 5.0

    private struct Sample {
        var cx: Double
        var cy: Double
        /// The view's width and height as a fraction of the picture's: one over the zoom.
        var size: Double
    }

    /// A stretch of the path from the picture at rest, through one or more zooms, back to rest. Between runs the camera is at
    /// rest and nothing is stored.
    private struct Run {
        var start: TimeInterval
        var samples: [Sample]
    }

    let frameSize: CGSize
    private let runs: [Run]

    /// False when the picture is never cropped.
    var hasZoom: Bool { !runs.isEmpty }

    /// `segments` may be in any order and may overlap (the person can drag one over another): the one that started last wins.
    init(segments: [ZoomSegment], frameSize: CGSize, rules: ZoomRules = .standard) {
        self.frameSize = frameSize
        guard frameSize.width > 0, frameSize.height > 0 else {
            runs = []
            return
        }
        let usable = segments.filter { $0.scale > 1 && $0.end > $0.start && $0.start.isFinite && $0.end.isFinite }
            .sorted { $0.start < $1.start }
        runs = Self.simulate(usable, frame: frameSize, rules: rules)
    }

    /// The part of the video in view at `time`, in pixels of the video (origin at the top-left). Always inside the video, always
    /// the video's own proportions.
    func rect(at time: TimeInterval) -> CGRect {
        let whole = CGRect(origin: .zero, size: frameSize)
        guard time.isFinite, let first = runs.first, time >= first.start else { return whole }
        var low = 0, high = runs.count
        while high - low > 1 {
            let middle = (low + high) / 2
            if runs[middle].start <= time { low = middle } else { high = middle }
        }
        let run = runs[low]
        let position = (time - run.start) / Self.step
        let index = Int(position)
        guard index + 1 < run.samples.count else { return whole }
        let a = run.samples[index], b = run.samples[index + 1]
        let fraction = position - Double(index)
        return Self.rect(
            centerX: a.cx + (b.cx - a.cx) * fraction, centerY: a.cy + (b.cy - a.cy) * fraction,
            size: a.size + (b.size - a.size) * fraction, in: frameSize
        )
    }

    /// The view of that size around that point, moved inside the video when it would stick out.
    private static func rect(centerX: Double, centerY: Double, size: Double, in frame: CGSize) -> CGRect {
        let fraction = min(max(size, 0.02), 1)
        let width = frame.width * fraction, height = frame.height * fraction
        let x = min(max(centerX - width / 2, 0), frame.width - width)
        let y = min(max(centerY - height / 2, 0), frame.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: Simulation

    private static func simulate(_ segments: [ZoomSegment], frame: CGSize, rules: ZoomRules) -> [Run] {
        let rateIn = rate / max(rules.zoomInDuration, 0.05)
        let rateOut = rate / max(rules.zoomOutDuration, 0.05)
        let middle = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let rest = Sample(cx: middle.x, cy: middle.y, size: 1)
        var runs: [Run] = []
        var index = 0
        while index < segments.count {
            let first = index
            var next = index
            var time = segments[index].start
            var state = rest
            var speed = Sample(cx: 0, cy: 0, size: 0)
            var samples = [rest]
            while true {
                while next < segments.count, segments[next].start <= time { next += 1 }
                // Of the zooms that have started, the latest one still going decides.
                var active: ZoomSegment?
                var candidate = next - 1
                while candidate >= first {
                    if segments[candidate].end > time {
                        active = segments[candidate]
                        break
                    }
                    candidate -= 1
                }
                var target = rest
                var spring = rateOut
                if let active {
                    let size = 1 / active.scale
                    let look = active.focusPoint(at: time) ?? middle
                    let halfWidth = frame.width * size / 2, halfHeight = frame.height * size / 2
                    target = Sample(
                        cx: min(max(look.x, halfWidth), frame.width - halfWidth),
                        cy: min(max(look.y, halfHeight), frame.height - halfHeight),
                        size: size
                    )
                    spring = rateIn
                }
                let decay = exp(-spring * step)
                advance(&state.cx, &speed.cx, to: target.cx, rate: spring, decay: decay)
                advance(&state.cy, &speed.cy, to: target.cy, rate: spring, decay: decay)
                advance(&state.size, &speed.size, to: target.size, rate: spring, decay: decay)
                time += step
                samples.append(state)
                if active == nil, abs(state.size - 1) < 1e-4 { break }
            }
            runs.append(Run(start: segments[first].start, samples: samples))
            index = next
        }
        return runs
    }

    /// One step of a critically damped spring, exact for a target that does not move during the step.
    private static func advance(_ value: inout Double, _ speed: inout Double, to target: Double, rate: Double, decay: Double) {
        let distance = value - target
        let carried = (speed + rate * distance) * step
        value = target + (distance + carried) * decay
        speed = (speed - rate * carried) * decay
    }
}
