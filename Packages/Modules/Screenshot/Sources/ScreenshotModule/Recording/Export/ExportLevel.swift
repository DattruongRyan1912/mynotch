import AVFoundation
import CoreGraphics
import Foundation

/// How good the exported file is. Both are H.264 with AAC in an MP4, which opens everywhere.
nonisolated enum ExportLevel: String, Codable, CaseIterable, Sendable {
    /// For sending in a chat: at most 1080p and 30 fps, a few megabits a second.
    case chat
    /// The recording's own resolution and frame rate, as large as H.264 can be: 4096 wide.
    case high

    var title: String {
        switch self {
        case .chat: "Gửi chat"
        case .high: "Chất lượng cao"
        }
    }

    /// What the exported file is, for a recording of `size` pixels at `fps`.
    func plan(forVideoOfSize size: CGSize, fps: Int) -> ExportPlan {
        let recorded = max(fps, 1)
        switch self {
        case .chat:
            // A box of 1920×1080, on its side for a recording taller than it is wide, so a portrait window fits too.
            let box = size.height > size.width ? CGSize(width: 1080, height: 1920) : CGSize(width: 1920, height: 1080)
            let fitted = ExportPlan.fit(size, inside: box)
            let frameRate = min(recorded, 30)
            return ExportPlan(
                size: fitted, frameRate: frameRate,
                videoBitrate: ExportPlan.bitrate(for: fitted, fps: frameRate, bitsPerPixel: 0.08, within: 4_000_000...6_000_000),
                audioBitrate: 128_000
            )
        case .high:
            // 4096 wide at most, and what H.264 level 5.2 takes, the highest every player is sure to open: 36 864 macroblocks
            // (16×16 pixels) in a frame, which is 4096×2304, and 2 073 600 macroblocks a second, which at 60 frames a second is
            // 34 560 in a frame, a little over 3840×2160. The encoder will go on to level 6 when asked for more, and a file at
            // level 6 is one many players and hardware decoders refuse. The frame rate is the recording's; what gives is the size.
            let macroblocks = min(ExportPlan.maximumFrameMacroblocks, ExportPlan.maximumMacroblocksPerSecond / recorded)
            let fitted = ExportPlan.fit(
                size, inside: CGSize(width: 4096, height: CGFloat.greatestFiniteMagnitude), maximumMacroblocks: macroblocks
            )
            return ExportPlan(
                size: fitted, frameRate: recorded,
                videoBitrate: ExportPlan.bitrate(for: fitted, fps: recorded, bitsPerPixel: 0.1, within: 8_000_000...60_000_000),
                audioBitrate: 192_000
            )
        }
    }
}

/// The picture, speed and sound of an exported file.
nonisolated struct ExportPlan: Equatable, Sendable {
    /// Pixels; both sides even.
    var size: CGSize
    var frameRate: Int
    var videoBitrate: Int
    var audioBitrate: Int

    /// What `AVAssetWriter` is told for the picture. The hardware encoder is the system's first choice but is not demanded: an
    /// export is not real time, and a Mac without it still gets its file.
    var videoSettings: [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                // Every frame is stored in the order it is shown, so the first one starts at 0 in every player and tool, none
                // of which then has to know how to skip the delay a reordering encoder leaves (and the sound cannot slip by it).
                AVVideoAllowFrameReorderingKey: false,
            ] as [String: Any],
            // What the compositor's pictures are tagged with: BT.709, which shares sRGB's primaries.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
    }

    /// Stereo whatever was recorded: a voice alone is copied to both sides, and sound from the system keeps its two.
    var audioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: RecordingMedia.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: audioBitrate,
        ]
    }

    /// H.264 level 5.2: macroblocks in a frame, and a second's worth.
    static let maximumFrameMacroblocks = 36_864
    static let maximumMacroblocksPerSecond = 2_073_600

    /// The 16×16 blocks a picture of `size` takes: each side is counted up to whole blocks, as the encoder does.
    static func macroblocks(of size: CGSize) -> Int {
        Int((size.width / 16).rounded(.up) * (size.height / 16).rounded(.up))
    }

    /// `size` scaled down, never up, to fit inside `box` and to take no more than `maximumMacroblocks`, with the same proportions
    /// and both sides even.
    static func fit(_ size: CGSize, inside box: CGSize, maximumMacroblocks: Int = .max) -> CGSize {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return CGSize(width: 2, height: 2) }
        var scale = min(1, box.width / size.width, box.height / size.height)
        // The picture is counted in whole blocks, so a size that is under the limit in pixels can be over it in blocks: start
        // from the pixels the blocks allow and take off a half percent at a time until the blocks fit.
        if maximumMacroblocks < .max { scale = min(scale, (Double(maximumMacroblocks) * 256 / (size.width * size.height)).squareRoot()) }
        while true {
            // The small margin keeps a size that fits exactly, 4096 of 6016 for instance, from losing two pixels to rounding.
            let fitted = CGSize(width: even(size.width * scale), height: even(size.height * scale))
            if macroblocks(of: fitted) <= maximumMacroblocks || scale < 0.01 { return fitted }
            scale *= 0.995
        }
    }

    private static func even(_ value: Double) -> Double {
        max((Double(Int(value + 1e-6)) / 2).rounded(.down) * 2, 2)
    }

    static func bitrate(for size: CGSize, fps: Int, bitsPerPixel: Double, within range: ClosedRange<Int>) -> Int {
        let wanted = size.width * size.height * Double(fps) * bitsPerPixel
        return min(max(Int(wanted), range.lowerBound), range.upperBound)
    }
}
