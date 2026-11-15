import AVFoundation
import CoreMedia
import Foundation

/// Why a recording could not be put together for the player or the exporter.
nonisolated enum RecordingCompositionError: Error, Equatable, Sendable {
    /// The project lists no segment.
    case noSegments
    /// Everything was cut.
    case nothingLeft
    /// A segment's file is not in the folder or does not open.
    case missingFile(String)
    /// A segment's file opens but has no picture.
    case noPicture(String)
    case failed(String)

    /// One line for the editor, in Vietnamese.
    var message: String {
        switch self {
        case .noSegments: "Bản quay chưa có đoạn nào"
        case .nothingLeft: "Đã cắt hết, không còn gì để xem"
        case .missingFile: "Không mở được một đoạn của bản quay"
        case .noPicture: "Một đoạn của bản quay không có hình"
        case .failed: "Không dựng được video từ bản quay"
        }
    }
}

/// A recording as the player and the exporter see it: the segments laid one after the other with the cuts taken out, and a
/// video composition that crops and scales each frame along the camera and draws the click rings. The files are never touched,
/// so every change is a new composition.
///
/// Everything the edits say is in recording time (the segments' time, without the pauses). The composition's own time is the
/// edited video's: `cutMap` goes between the two.
struct RecordingComposition {
    struct Options {
        /// What the output is drawn at; nil is the size of the recording. The camera's picture is scaled to fill it, so it
        /// should have the recording's proportions.
        var renderSize: CGSize?
        /// Frames a second of the output; nil is the recording's own. The composition asks for a frame at exactly this rate
        /// whatever the file holds.
        var frameRate: Int?

        init(renderSize: CGSize? = nil, frameRate: Int? = nil) {
            self.renderSize = renderSize
            self.frameRate = frameRate
        }
    }

    /// One timescale for every insertion, so the pieces of a cut recording meet exactly: 48 000 (sound) and 60 000 (the usual
    /// frame rates) both divide it.
    static let timescale: CMTimeScale = 240_000

    let composition: AVComposition
    let videoComposition: AVVideoComposition
    /// What a reader takes: the one picture track, and one sound track per source (microphone, then system sound).
    let videoTrack: AVCompositionTrack
    let audioTracks: [AVCompositionTrack]
    /// Of the edited video, in seconds.
    let duration: TimeInterval
    let cutMap: CutMap
    let camera: CameraPath
    let renderSize: CGSize
    let frameRate: Int

    func makePlayerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        return item
    }

    /// Opens the project's segments in `folder` and builds the composition. The project's `zoomSegments` (or, when the person
    /// has not edited the zooms, the plan made from `activity`), its `cuts` and `clickEffect` decide the rest.
    static func make(
        project: RecordingProject, folder: URL, activity: ActivityTrack, options: Options = Options()
    ) async throws(RecordingCompositionError) -> RecordingComposition {
        guard !project.segments.isEmpty else { throw .noSegments }
        let cutMap = CutMap(duration: project.duration, cuts: project.cuts)
        guard cutMap.editedDuration > 0 else { throw .nothingLeft }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw .failed("video track")
        }
        var audioTracks: [AVMutableCompositionTrack] = []
        do {
            try await insertPieces(of: project, in: folder, cutMap: cutMap, into: composition, video: videoTrack, audio: &audioTracks)
        } catch let error as RecordingCompositionError {
            throw error
        } catch {
            throw .failed(error.localizedDescription)
        }

        let size = CGSize(width: project.region.pixelWidth, height: project.region.pixelHeight)
        let renderSize = options.renderSize ?? size
        let frameRate = max(options.frameRate ?? project.fps, 1)
        let segments = project.zoomSegments ?? ZoomPlanner.plan(activity: activity, rules: project.zoomRules, duration: project.duration)
        let camera = CameraPath(segments: segments, frameSize: size, rules: project.zoomRules)
        let instruction = RecordingFrameInstruction(
            timeRange: CMTimeRange(start: .zero, duration: composition.duration), videoTrackID: videoTrack.trackID, camera: camera,
            clicks: project.clickEffect ? ClickEffect(clicks: activity.clicks, frameSize: size) : nil, cuts: cutMap
        )
        var configuration = AVVideoComposition.Configuration()
        configuration.customVideoCompositorClass = RecordingCompositor.self
        configuration.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.renderSize = renderSize
        configuration.instructions = [instruction]
        // What the files are tagged with: BT.709, which shares sRGB's primaries.
        configuration.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        configuration.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        configuration.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return RecordingComposition(
            composition: composition, videoComposition: AVVideoComposition(configuration: configuration), videoTrack: videoTrack,
            audioTracks: audioTracks,
            duration: composition.duration.seconds, cutMap: cutMap, camera: camera, renderSize: renderSize, frameRate: frameRate
        )
    }

    // MARK: Pieces

    /// What a segment's file offers: its picture and each sound track, with the stretch of the movie each really covers.
    private struct SegmentSource {
        /// The tracks do not keep their asset alive.
        var asset: AVURLAsset
        var video: (track: AVAssetTrack, range: CMTimeRange)
        var audio: [(track: AVAssetTrack, range: CMTimeRange)]
    }

    private static func ticks(_ seconds: TimeInterval) -> Int64 { Int64((seconds * Double(timescale)).rounded()) }

    private static func time(_ ticks: Int64) -> CMTime { CMTime(value: ticks, timescale: timescale) }

    /// Inserts what is kept of each segment, in order. All tracks of a piece take the same stretch of their file, so picture
    /// and sound stay together; the places are counted in whole ticks, so the pieces meet with no gap and no overlap.
    private static func insertPieces(
        of project: RecordingProject, in folder: URL, cutMap: CutMap, into composition: AVMutableComposition,
        video: AVMutableCompositionTrack, audio audioTracks: inout [AVMutableCompositionTrack]
    ) async throws {
        var sources: [Int: SegmentSource] = [:]
        var segmentStart: Int64 = 0
        var cursor: Int64 = 0
        for (index, segment) in project.segments.enumerated() {
            let length = ticks(segment.duration)
            defer { segmentStart += length }
            for kept in cutMap.kept {
                // The part of this segment that is kept, in ticks of the recording and then of the file.
                let low = max(ticks(kept.lowerBound), segmentStart), high = min(ticks(kept.upperBound), segmentStart + length)
                guard high > low else { continue }
                if sources[index] == nil { sources[index] = try await open(segment, in: folder) }
                let source = sources[index]!
                let wanted = CMTimeRange(start: time(low - segmentStart), end: time(high - segmentStart))
                try insert(wanted, of: source.video.track, available: source.video.range, at: cursor, into: video)
                for (position, sound) in source.audio.enumerated() {
                    while audioTracks.count <= position {
                        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                            throw RecordingCompositionError.failed("audio track")
                        }
                        audioTracks.append(track)
                    }
                    try insert(wanted, of: sound.track, available: sound.range, at: cursor, into: audioTracks[position])
                }
                cursor += high - low
            }
        }
    }

    /// Inserts `wanted` of `track` at `cursor`, cut to what the track really has; what it lacks stays a gap, and the next piece
    /// goes where it belongs all the same.
    private static func insert(
        _ wanted: CMTimeRange, of track: AVAssetTrack, available: CMTimeRange, at cursor: Int64, into destination: AVMutableCompositionTrack
    ) throws {
        let range = wanted.intersection(available)
        guard range.isValid, !range.isEmpty else { return }
        let offset = range.start - wanted.start
        try destination.insertTimeRange(range, of: track, at: time(cursor) + offset)
    }

    private static func open(_ segment: RecordingProject.Segment, in folder: URL) async throws -> SegmentSource {
        let url = folder.appending(path: segment.fileName)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw RecordingCompositionError.missingFile(segment.fileName)
        }
        let asset = AVURLAsset(url: url)
        let videoTracks: [AVAssetTrack], audioTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw RecordingCompositionError.missingFile(segment.fileName)
        }
        guard let video = videoTracks.first else { throw RecordingCompositionError.noPicture(segment.fileName) }
        var audio: [(track: AVAssetTrack, range: CMTimeRange)] = []
        for track in audioTracks { audio.append((track, try await track.load(.timeRange))) }
        return SegmentSource(asset: asset, video: (video, try await video.load(.timeRange)), audio: audio)
    }
}
