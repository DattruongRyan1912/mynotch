import AVFoundation
import Foundation

/// Opens what a recording that ended badly left behind, so the person gets back what was recorded.
///
/// A segment is written in fragments, so a file cut off by a crash still opens up to its last complete fragment. The one
/// exception is a segment that never wrote its first fragment (the first two seconds): nothing in it can be read.
nonisolated enum RecordingRecovery {
    /// Reads the folder, keeps every segment that opens, and saves the project as `interrupted` with the durations the files
    /// really have. A segment that cannot be read is left in the folder, listed nowhere. The activity loses what lies beyond
    /// the end of the video. Throws when the folder has no readable `project.json`.
    @concurrent static func recover(folder: URL) async throws -> RecordingProject {
        var project = try RecordingProject.load(from: folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        var segments: [RecordingProject.Segment] = []
        for name in names.filter({ $0.hasPrefix("segment-") && $0.hasSuffix(".mov") }).sorted() {
            guard let duration = await readableDuration(of: folder.appending(path: name)) else { continue }
            if var known = project.segments.first(where: { $0.fileName == name }) {
                // A segment closed properly keeps what its writer measured; the file can only confirm it.
                known.duration = min(known.duration, duration)
                segments.append(known)
            } else {
                segments.append(.init(fileName: name, captureStart: nil, duration: duration))
            }
        }
        project.segments = segments
        project.status = .interrupted
        try project.write(to: folder)
        if let track = try? ActivityTrack.load(from: folder) {
            try track.trimmed(to: project.duration).write(to: folder)
        }
        return project
    }

    /// The length of the video in a file when it opens and has a picture, nil otherwise.
    @concurrent static func readableDuration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true,
              let duration = try? await asset.load(.duration), duration.seconds > 0,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { return nil }
        return duration.seconds
    }
}
