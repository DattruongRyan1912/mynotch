import Foundation

/// A stretch of the recording the person cut out, in recording time (pauses already left out, as in `ActivityTrack`).
nonisolated struct CutRange: Codable, Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
}

/// What is left of a recording once the cuts are taken out, and the time that passes between the two: the edited video's time
/// (what a player shows) and the recording's (what the activity, the zooms and the clicks are measured in).
nonisolated struct CutMap: Equatable, Sendable {
    /// The whole recording.
    let duration: TimeInterval
    /// What stays, in recording time: in order, apart from each other, never empty.
    let kept: [Range<TimeInterval>]

    /// Cuts may come in any order, overlap, touch, or reach beyond the recording; they are put in order and joined, and what
    /// lies outside `0...duration` or is not a number is ignored.
    init(duration: TimeInterval, cuts: [CutRange]) {
        let total = duration.isFinite ? max(duration, 0) : 0
        self.duration = total
        let usable = cuts.filter { $0.start.isFinite && $0.end.isFinite }
            .map { CutRange(start: max($0.start, 0), end: min($0.end, total)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var merged: [CutRange] = []
        for cut in usable {
            if let last = merged.last, cut.start <= last.end {
                merged[merged.count - 1].end = max(last.end, cut.end)
            } else {
                merged.append(cut)
            }
        }
        var kept: [Range<TimeInterval>] = []
        var position = 0.0
        for cut in merged {
            if cut.start > position { kept.append(position..<cut.start) }
            position = cut.end
        }
        if position < total { kept.append(position..<total) }
        self.kept = kept
    }

    /// The cuts as they count: in order, joined, inside the recording.
    var cuts: [CutRange] {
        var result: [CutRange] = []
        var position = 0.0
        for range in kept {
            if range.lowerBound > position { result.append(CutRange(start: position, end: range.lowerBound)) }
            position = range.upperBound
        }
        if position < duration { result.append(CutRange(start: position, end: duration)) }
        return result
    }

    /// The length of the edited video.
    var editedDuration: TimeInterval { kept.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } }

    /// The moment of the recording that the edited video shows at `time`; nil beyond its end. The first moment after a cut
    /// belongs to what follows it.
    func recordingTime(forEdited time: TimeInterval) -> TimeInterval? {
        guard let (range, offset) = locate(edited: time) else { return nil }
        return range.lowerBound + (time - offset)
    }

    /// The stretch that is playing at edited time `time`, as it is in recording time. Clicks that happened before it began
    /// belong to a part of the video that is not there any more.
    func keptRange(forEdited time: TimeInterval) -> Range<TimeInterval>? { locate(edited: time)?.range }

    /// What to draw at edited time `time`: its moment of the recording and the stretch that plays. A time at or past the end
    /// counts as the last moment and one before the start as the first, never as nothing: the composition counts its pieces in
    /// whole ticks, so it can be a few microseconds longer than the stretches add up to, and a frame asked for in that sliver
    /// must still come from the end of the recording. Nil only for a time that is not a number, or when nothing is left.
    func nearest(toEdited time: TimeInterval) -> (time: TimeInterval, range: Range<TimeInterval>)? {
        guard time.isFinite, !kept.isEmpty else { return nil }
        let clamped = min(max(time, 0), editedDuration.nextDown)
        guard let (range, offset) = locate(edited: clamped) else { return nil }
        return (range.lowerBound + (clamped - offset), range)
    }

    /// Where a moment of the recording is in the edited video; nil when it was cut.
    func editedTime(forRecording time: TimeInterval) -> TimeInterval? {
        var offset = 0.0
        for range in kept {
            if range.contains(time) { return offset + (time - range.lowerBound) }
            offset += range.upperBound - range.lowerBound
        }
        return nil
    }

    private func locate(edited time: TimeInterval) -> (range: Range<TimeInterval>, offset: TimeInterval)? {
        guard time.isFinite, time >= 0 else { return nil }
        var offset = 0.0
        for range in kept {
            let length = range.upperBound - range.lowerBound
            if time < offset + length { return (range, offset) }
            offset += length
        }
        return nil
    }
}
