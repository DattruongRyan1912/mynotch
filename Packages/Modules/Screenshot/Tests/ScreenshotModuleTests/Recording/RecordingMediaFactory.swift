import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import ScreenshotModule

/// Frames and sound made in memory: a recording test never captures a screen or opens a microphone.
enum RecordingMediaFactory {
    /// A BGRA frame in IOSurface memory, like the ones ScreenCaptureKit hands out, painted with a gradient that depends on `index`
    /// so successive frames differ; `detailed: false` fills it with one grey, which is cheap for a very large frame.
    static func frame(width: Int, height: Int, index: Int = 0, detailed: Bool = true) -> VideoFrameBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        let pixelBuffer = buffer!
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard detailed else {
            memset(base, 90 + Int32(index & 63), rowBytes * height)
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return VideoFrameBuffer(pixelBuffer)
        }
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                base[offset] = UInt8((x * 3 + index * 5) & 255)
                base[offset + 1] = UInt8((y * 5) & 255)
                base[offset + 2] = UInt8((index * 7) & 255)
                base[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return VideoFrameBuffer(pixelBuffer)
    }

    /// `frames` frames of a tone starting at `start` seconds on the capture clock.
    static func audio(
        start: TimeInterval, frames: Int, sampleRate: Double = 48_000, channels: Int = 1, interleavedInt16: Bool = false
    ) -> CMSampleBuffer {
        let format = interleavedInt16
            ? AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: true)!
            : AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            let value = 0.3 * sin(Double(frame) * 2 * .pi * 440 / sampleRate)
            if interleavedInt16 {
                for channel in 0..<channels { buffer.int16ChannelData![0][frame * channels + channel] = Int16(value * 32_000) }
            } else {
                for channel in 0..<channels { buffer.floatChannelData![channel][frame] = Float(value) }
            }
        }
        return AudioNormalizer.sampleBuffer(from: buffer, at: CMTime(seconds: start, preferredTimescale: 1_000_000_000))!
    }

    static func time(_ seconds: TimeInterval) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 1_000_000_000) }
}

/// A pixel buffer that may cross threads: a test hands each one over and never touches it again.
struct VideoFrameBuffer: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    init(_ pixelBuffer: CVPixelBuffer) { self.pixelBuffer = pixelBuffer }
}

/// What a movie on disk contains, read back with AVFoundation, as a player or an exporter would.
struct MediaProbe {
    var isPlayable: Bool
    var duration: TimeInterval
    var videoSize: CGSize?
    var videoCodec: FourCharCode?
    /// What the file's picture costs, in bits per second, as the system estimates it.
    var videoDataRate: Float = 0
    var videoFrames: Int
    /// The stamp of each video sample, earliest first.
    var videoTimes: [TimeInterval]
    var audioDurations: [TimeInterval]
    var audioStarts: [TimeInterval]
    var audioCodecs: [FourCharCode] = []
    var audioChannels: [Int] = []

    static func read(_ url: URL) async throws -> MediaProbe {
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.load(.tracks)
        var probe = MediaProbe(isPlayable: playable, duration: duration, videoFrames: 0, videoTimes: [], audioDurations: [], audioStarts: [])
        for track in tracks where track.mediaType == .audio {
            let range = try await track.load(.timeRange)
            probe.audioDurations.append(range.duration.seconds)
            probe.audioStarts.append(range.start.seconds)
            if let description = try await track.load(.formatDescriptions).first {
                probe.audioCodecs.append(CMFormatDescriptionGetMediaSubType(description))
                probe.audioChannels.append(Int(CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee.mChannelsPerFrame ?? 0))
            }
        }
        if let video = tracks.first(where: { $0.mediaType == .video }) {
            probe.videoSize = try await video.load(.naturalSize)
            probe.videoDataRate = try await video.load(.estimatedDataRate)
            if let description = try await video.load(.formatDescriptions).first {
                probe.videoCodec = CMFormatDescriptionGetMediaSubType(description)
            }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
            reader.add(output)
            reader.startReading()
            while let sample = output.copyNextSampleBuffer() {
                let count = CMSampleBufferGetNumSamples(sample)
                probe.videoFrames += count
                // A buffer may hold many samples (an MP4 groups them), each with a stamp of its own.
                var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
                var filled = 0
                if count > 0, CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timings, entriesNeededOut: &filled) == noErr {
                    probe.videoTimes += timings.prefix(filled).map { $0.presentationTimeStamp.seconds }
                } else if count > 0 {
                    probe.videoTimes.append(sample.presentationTimeStamp.seconds)
                }
            }
            // The order the frames are shown in, which a file with reordered frames does not store them in.
            probe.videoTimes.sort()
        }
        return probe
    }
}

/// A folder for one test, removed afterwards.
final class TestFolder {
    let url: URL

    init(_ label: String = "recording") throws {
        url = FileManager.default.temporaryDirectory.appending(path: "MyNotchTests-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func file(_ name: String) -> URL { url.appending(path: name) }
}
