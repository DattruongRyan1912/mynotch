import Foundation

/// What the person can change in the editor, as one value, so undo and redo take the whole of it back and forth.
nonisolated struct RecordingEdit: Equatable, Sendable {
    /// In recording time.
    var cuts: [CutRange]
    /// Nil until the zooms are first edited: they then come from the activity. See `RecordingProject.zoomSegments`.
    var zoomSegments: [ZoomSegment]?
    var clickEffect: Bool

    init(of project: RecordingProject) {
        cuts = CutMap(duration: project.duration, cuts: project.cuts).cuts
        zoomSegments = project.zoomSegments
        clickEffect = project.clickEffect
    }

    /// `project` with this edit written into it.
    func applied(to project: RecordingProject) -> RecordingProject {
        var result = project
        result.cuts = cuts
        result.zoomSegments = zoomSegments
        result.clickEffect = clickEffect
        return result
    }
}
