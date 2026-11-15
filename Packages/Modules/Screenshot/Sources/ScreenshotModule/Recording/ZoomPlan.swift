import CoreGraphics
import Foundation

/// What decides where a recording zooms and how the picture moves. Times are seconds, distances are pixels of the video.
nonisolated struct ZoomRules: Codable, Equatable, Sendable {
    /// How far a click zooms in. The editor's slider keeps it between 1.25 and 3.
    var scale = 2.0
    /// The time the picture takes to get about 96% of the way in (a critically damped spring: it starts and ends softly).
    var zoomInDuration = 0.5
    /// The same for the way out.
    var zoomOutDuration = 0.6
    /// A zoom lasts until this long has passed with no click, no pointer movement and no key.
    var idleTimeout = 1.5
    /// Two zooms closer than this (the time between one's end and the next one's start) are one: the picture stays in.
    var mergeGap = 2.5
    /// A pointer that moved less than this since the last activity is a resting hand, not activity.
    var minimumMovement = 6.0
    /// Whether the camera pans to follow pointer movements while zoomed. Default is false (zoom in on click, hold, and zoom out).
    var followPointer = false

    static let standard = ZoomRules()

    init() {}

    /// Fields a later version adds are read with their default when a file has none.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = ZoomRules()
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? standard.scale
        zoomInDuration = try container.decodeIfPresent(Double.self, forKey: .zoomInDuration) ?? standard.zoomInDuration
        zoomOutDuration = try container.decodeIfPresent(Double.self, forKey: .zoomOutDuration) ?? standard.zoomOutDuration
        idleTimeout = try container.decodeIfPresent(Double.self, forKey: .idleTimeout) ?? standard.idleTimeout
        mergeGap = try container.decodeIfPresent(Double.self, forKey: .mergeGap) ?? standard.mergeGap
        minimumMovement = try container.decodeIfPresent(Double.self, forKey: .minimumMovement) ?? standard.minimumMovement
        followPointer = try container.decodeIfPresent(Bool.self, forKey: .followPointer) ?? standard.followPointer
    }
}

/// One stretch of the recording that is zoomed in, in recording time (pauses and cuts do not change it).
nonisolated struct ZoomSegment: Codable, Equatable, Sendable {
    /// Where the camera looks: a pixel of the video, at a moment.
    nonisolated struct Focus: Codable, Equatable, Sendable {
        var t: TimeInterval
        var x: Double
        var y: Double
    }

    /// When the picture starts to zoom in.
    var start: TimeInterval
    /// When it starts to zoom out again; it is whole `ZoomRules.zoomOutDuration` later.
    var end: TimeInterval
    var scale: Double
    /// Where the camera looks while zoomed, sorted by time: the clicks, and the pointer a few times a second. Before the first
    /// and after the last the camera stays on that one. Empty means the middle of the picture.
    var focus: [Focus]
    /// Added by the person, not planned from the activity.
    var manual = false

    init(start: TimeInterval, end: TimeInterval, scale: Double, focus: [Focus] = [], manual: Bool = false) {
        self.start = start
        self.end = end
        self.scale = scale
        self.focus = focus
        self.manual = manual
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        scale = try container.decode(Double.self, forKey: .scale)
        focus = try container.decodeIfPresent([Focus].self, forKey: .focus) ?? []
        manual = try container.decodeIfPresent(Bool.self, forKey: .manual) ?? false
    }

    /// Where the camera looks at `time`: the focus points joined by straight lines, held beyond the first and the last.
    func focusPoint(at time: TimeInterval) -> CGPoint? {
        guard let first = focus.first, let last = focus.last else { return nil }
        if time <= first.t { return CGPoint(x: first.x, y: first.y) }
        if time >= last.t { return CGPoint(x: last.x, y: last.y) }
        var low = 0, high = focus.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if focus[middle].t <= time { low = middle } else { high = middle }
        }
        let a = focus[low], b = focus[high]
        let fraction = b.t > a.t ? (time - a.t) / (b.t - a.t) : 1
        return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }
}
