import Foundation

/// What a recording that was just made starts out with in the editor: the person's own settings. Written into `project.json`
/// once, when the recording ends, and never again: reopening it from the list keeps what was chosen for it since.
nonisolated struct RecordingDefaults: Equatable, Sendable {
    var exportLevel: ExportLevel
    var zoomScale: Double
    /// Seconds without activity before a zoom goes back out.
    var zoomHoldSeconds: Double
    var clickEffect: Bool

    func apply(to project: inout RecordingProject) {
        project.exportLevel = exportLevel
        project.zoomRules.scale = zoomScale
        project.zoomRules.idleTimeout = zoomHoldSeconds
        project.clickEffect = clickEffect
    }

    /// Reads `project.json` in `folder`, applies the defaults and writes it back.
    func write(to folder: URL) throws {
        var project = try RecordingProject.load(from: folder)
        apply(to: &project)
        try project.write(to: folder)
    }
}
