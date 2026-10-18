import AVFoundation
import VideoToolbox

/// Which audio a track carries.
nonisolated enum AudioTrackKind: Hashable, Sendable {
    case microphone
    case system

    /// One channel is enough for a voice; what the system plays is stereo.
    var channels: Int { self == .microphone ? 1 : 2 }
}

/// How the files of a recording are encoded. These are the first files, edited and exported later, so quality matters more than
/// size, but a recording is never deleted by itself, so size matters too.
nonisolated enum RecordingMedia {
    static let sampleRate = 48_000

    /// HEVC on the hardware encoder. Hardware H.264 stops at 4096×2304, so a 5K display could not be recorded at its own
    /// resolution (`canApply` says yes and the first frame fails), and HEVC takes about half the room. The export is H.264.
    /// No frame reordering, so every frame is written in the order it was shown. Keyframes every 2 s, the size of a fragment.
    static func videoSettings(width: Int, height: Int, fps: Int, requireHardware: Bool = true) -> [String: Any] {
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate(width: width, height: height, fps: fps),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoAllowFrameReorderingKey: false,
            ] as [String: Any],
            // What the encoder converts the pictures to, and so what the file says it is. BT.709 shares sRGB's primaries,
            // which is what the stream is asked for.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        if requireHardware {
            settings[AVVideoEncoderSpecificationKey] = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true]
        }
        return settings
    }

    /// About 0.08 bit per pixel per frame, 10 Mbit/s at 1080p60 and 40 Mbit/s at 4K60, kept between 8 and 50.
    static func bitrate(width: Int, height: Int, fps: Int) -> Int {
        let wanted = Double(width * height * fps) * 0.08
        return Int(min(max(wanted, 8_000_000), 50_000_000))
    }

    static func audioSettings(for kind: AudioTrackKind) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: kind.channels,
            AVEncoderBitRateKey: kind == .microphone ? 96_000 : 128_000,
        ]
    }
}
