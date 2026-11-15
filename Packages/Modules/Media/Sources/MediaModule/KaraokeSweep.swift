import AppKit
import CoreText
import Foundation

/// How a line is filled while it is sung, as pure numbers: where the fill is now, in points from the left edge of the
/// text, and the moves that take it to the end of the line. The view turns the moves into one animation that the render
/// server runs, so nothing is redrawn per frame.
nonisolated struct KaraokeSweep: Equatable, Sendable {
    /// Moves to `x` in `duration` seconds on the clock the view runs. A step that keeps `x` is a wait.
    struct Step: Equatable, Sendable {
        var duration: Double
        var x: Double
    }

    /// The shortest step: a word with no length is a jump, and an animation wants time for it.
    static let minimumStep = 0.001

    /// Where the fill is at the moment of the sweep.
    var start: Double
    /// Where it goes from there, in order; none when the line is filled or the clock stands still.
    var steps: [Step]

    /// Where the fill ends up.
    var finish: Double { steps.last?.x ?? start }

    /// How long the steps take together.
    var duration: Double { steps.reduce(0) { $0 + $1.duration } }

    /// When each of the points (the start, then the end of each step) is reached, as a share of `duration`, 0 first and 1 last;
    /// empty without steps. What a keyframe animation wants for the values `start` and the steps' `x`.
    var keyTimes: [Double] {
        let total = duration
        guard total > 0 else { return [] }
        var elapsed = 0.0
        var times = [0.0]
        for step in steps {
            elapsed += step.duration
            times.append(min(elapsed / total, 1))
        }
        times[times.count - 1] = 1
        return times
    }

    /// The sweep of a line at `position` seconds into the track, the clock running `rate` times as fast as the track.
    /// `edges` holds where each word starts and, last, the width of the text: one more than there are words. The fill
    /// crosses a word evenly while it is sung and waits in the gaps. A rate that is zero or less (paused), or not a number,
    /// leaves the fill where it is; a position that is not a number leaves the line empty. Edges that ever run backwards (or are
    /// not numbers), which is what right-to-left text measures, can make no sweep: the whole line is filled and nothing moves.
    static func make(words: [LyricWord], edges: [Double], position: Double, rate: Double) -> KaraokeSweep {
        guard !words.isEmpty, edges.count == words.count + 1, !position.isNaN else { return KaraokeSweep(start: 0, steps: []) }
        guard (1..<edges.count).allSatisfy({ edges[$0] >= edges[$0 - 1] }), edges[edges.count - 1].isFinite else {
            return KaraokeSweep(start: edges.last.flatMap { $0.isFinite ? $0 : nil } ?? 0, steps: [])
        }
        // Where the fill is, in media time: begin and end of each word, joined by waits.
        var points: [(time: Double, x: Double)] = []
        for (index, word) in words.enumerated() {
            points.append((word.begin, edges[index]))
            points.append((word.end, edges[index + 1]))
        }
        let start: Double
        if let after = points.firstIndex(where: { $0.time > position }) {
            // Before the first point nothing is filled; else between two points, which is a wait when they share an x.
            if after == 0 {
                start = edges[0]
            } else {
                let (before, next) = (points[after - 1], points[after])
                start = before.x + (next.x - before.x) * (position - before.time) / (next.time - before.time)
            }
        } else {
            start = edges[edges.count - 1]
        }
        guard rate > 0 else { return KaraokeSweep(start: start, steps: []) }
        var steps: [Step] = []
        var time = position
        var x = start
        for point in points where point.time > position {
            let elapsed = point.time - time
            time = point.time
            // Nothing changes: the end of a word where the next begins.
            if elapsed <= 0, point.x == x { continue }
            steps.append(Step(duration: max(elapsed, minimumStep) / rate, x: point.x))
            x = point.x
        }
        return KaraokeSweep(start: start, steps: steps)
    }

    /// Where the soft edge of the fill starts when the fill is at `x`: the fill fades out over `feather` points, so the edge is
    /// that much before the text when nothing is filled and on its last letter when all of it is, and it moves evenly between.
    static func edge(forFill x: Double, width: Double, feather: Double) -> Double {
        guard width > 0 else { return 0 }
        return x - feather * (1 - x / width)
    }
}

/// How a line is made to fit the row it is in.
nonisolated enum KaraokeFit {
    /// The smallest a line is shrunk to, as a share of its size; what is still wider is cut off at its end.
    static let minimumScale = 0.6
    /// Measurements made to find a size that fits: the first, then a step and a new measurement each.
    static let maximumSteps = 4

    /// The font size at which a line fits `available` points, found by measuring the line at the size being tried: text is
    /// not a fixed number of times as wide at a size that many times smaller (a font's tracking grows as it shrinks), so a
    /// measurement made at the full size cannot be scaled. `measure` gives the line's width at a size. The line is kept a point
    /// narrower than the row, since a text layer may measure a hair wider than CoreText does. The size is `base` for a line that
    /// fits and never below `base * minimumScale`, where a line that still does not fit is cut off.
    static func size(base: Double, available: Double, measure: (Double) -> Double) -> Double {
        let target = available - 1
        let smallest = base * minimumScale
        var size = base
        var width = measure(size)
        for _ in 0..<maximumSteps {
            guard width > target, size > smallest else { break }
            size = max(size * target / width, smallest)
            width = measure(size)
        }
        return size
    }

    /// Whether any part of `text` runs right to left (Arabic, Hebrew, and a mixed line that has some): the offsets CoreText
    /// gives for such a line are positions from its right, which no left-to-right fill can follow.
    static func hasRightToLeftRun(_ text: String, font: NSFont) -> Bool {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        return runs.contains { CTRunGetStatus($0).contains(.rightToLeft) }
    }
}
