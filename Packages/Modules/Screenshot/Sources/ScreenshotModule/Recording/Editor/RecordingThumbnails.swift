import AVFoundation
import CoreGraphics

/// The small pictures of the timeline's strip, taken straight from the recording's files: no zoom, no rings, no cuts.
nonisolated enum RecordingThumbnails {
    /// Pictures at the middle of each of `count` equal parts of `asset`, given to `onImage` (the part's number and its picture)
    /// as each is ready. A part that cannot be read is left out. The generator is told a half part either way is good enough, so
    /// it takes the nearest picture that is cheap to decode, not one that needs decoding from the keyframe before.
    @MainActor
    static func make(of asset: AVAsset, duration: TimeInterval, count: Int, maximumSize: CGSize, onImage: (Int, CGImage) -> Void) async {
        guard duration > 0, count > 0 else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        let half = CMTime(seconds: duration / Double(count) / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = half
        generator.requestedTimeToleranceAfter = half
        let times = (0..<count).map { CMTime(seconds: (Double($0) + 0.5) / Double(count) * duration, preferredTimescale: 600) }
        for await result in generator.images(for: times) {
            if case .success(let requested, let image, _) = result, let index = times.firstIndex(of: requested) {
                onImage(index, image)
            }
        }
    }
}
