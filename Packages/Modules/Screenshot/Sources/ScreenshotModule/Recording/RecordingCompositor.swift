import AVFoundation
import CoreMedia
import CoreVideo

/// What the compositor needs to draw each frame of one edited video, handed to it with the instruction because AVFoundation
/// makes the compositor itself with no arguments.
nonisolated final class RecordingFrameInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    /// The picture changes from frame to frame even when the source does not: the camera moves over a screen that stands still.
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let videoTrackID: CMPersistentTrackID
    let camera: CameraPath
    /// Nil when the click effect is off.
    let clicks: ClickEffect?
    let cuts: CutMap

    init(timeRange: CMTimeRange, videoTrackID: CMPersistentTrackID, camera: CameraPath, clicks: ClickEffect?, cuts: CutMap) {
        self.timeRange = timeRange
        self.videoTrackID = videoTrackID
        self.camera = camera
        self.clicks = clicks
        self.cuts = cuts
        requiredSourceTrackIDs = [NSNumber(value: videoTrackID)]
        super.init()
    }
}

/// Draws the edited video for the player and the exporter: for each frame the camera's part of the picture, scaled to the
/// output, with the click rings. It is asked for a frame every `frameDuration` of the composition whatever the source does, so
/// a screen that stood still, which the file holds as a frame every half second or so, still gets a smooth camera.
nonisolated final class RecordingCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let bufferAttributes: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

    private let renderer = FrameRenderer()

    var sourcePixelBufferAttributes: [String: any Sendable]? { Self.bufferAttributes }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { Self.bufferAttributes }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? RecordingFrameInstruction,
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "MyNotch.RecordingCompositor", code: 1))
            return
        }
        // The edited video's time to the recording's, which is what the camera, the rings and the cuts are measured in.
        let editedTime = request.compositionTime.seconds
        let located = instruction.cuts.nearest(toEdited: editedTime)
        let recordingTime = located?.time ?? editedTime
        let source = request.sourceFrame(byTrackID: instruction.videoTrackID)
        var crop = instruction.camera.rect(at: recordingTime)
        var rings = instruction.clicks?.rings(
            at: recordingTime, notBefore: located?.range.lowerBound ?? 0
        ) ?? []
        if let source, instruction.camera.frameSize.width > 0 {
            // The camera and the rings work in the pixels the project says the video has; the file is what it is.
            let factor = CGFloat(CVPixelBufferGetWidth(source)) / instruction.camera.frameSize.width
            if factor != 1 {
                crop = crop.applying(CGAffineTransform(scaleX: factor, y: factor))
                rings = rings.map { ClickEffect.Ring(x: $0.x * factor, y: $0.y * factor, radius: $0.radius * factor, opacity: $0.opacity) }
            }
        }
        renderer.render(source: source, crop: crop, rings: rings, into: output)
        request.finish(withComposedVideoFrame: output)
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
