import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
@testable import ScreenshotModule

/// A recording made in the test: the segments are written by the real `SegmentWriter` (HEVC and AAC, in fragments), so the
/// composition is tested on the files the app makes. Nothing is captured and no microphone is opened.
struct SampleRecording {
    /// One segment: how long it is and how often a frame arrives (a still screen sends one every half second or so).
    struct Part {
        var seconds: Double
        var frameInterval = 1.0 / 30
    }

    let folder: TestFolder
    var project: RecordingProject
    var activity: ActivityTrack

    var size: CGSize { CGSize(width: project.region.pixelWidth, height: project.region.pixelHeight) }

    /// `picture` is the frame for a moment of the recording (recording time: pauses left out) and `amplitude`, when there is
    /// sound, how loud the tone is then. Each part is its own segment, as each pause makes one.
    static func make(
        parts: [Part], width: Int = 160, height: Int = 90, clicks: [ActivityTrack.Click] = [],
        picture: (Double) -> CVPixelBuffer, amplitude: ((Double) -> Float)? = nil
    ) async throws -> SampleRecording {
        let folder = try TestFolder("composition")
        let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: Double(width) / 2, height: Double(height) / 2), scale: 2)
        var project = RecordingProject(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1_000), status: .finished,
            region: RecordingRegion(fullScreen: display)!, fps: 30, hasMicrophone: amplitude != nil, hasSystemAudio: false
        )
        var offset = 0.0
        for (index, part) in parts.enumerated() {
            let name = "segment-\(String(format: "%03d", index + 1)).mov"
            let start = 1_000 + Double(index) * 100
            let writer = try SegmentWriter(
                url: folder.file(name), width: width, height: height, fps: 30, audio: amplitude == nil ? [] : [.microphone],
                backpressure: .wait
            )
            var soundFrames = 0
            func feedSound(upTo seconds: Double) {
                guard let amplitude else { return }
                while Double(soundFrames) / 48_000 < seconds {
                    writer.appendAudio(tone(start: start, firstFrame: soundFrames, frames: 1_024, recordingOffset: offset, amplitude: amplitude), kind: .microphone)
                    soundFrames += 1_024
                }
            }
            var index = 0
            while Double(index) * part.frameInterval < part.seconds - 1e-9 {
                let local = Double(index) * part.frameInterval
                writer.appendVideo(picture(offset + local), at: RecordingMediaFactory.time(start + local))
                feedSound(upTo: local + 0.05)
                index += 1
            }
            feedSound(upTo: part.seconds)
            let summary = try await finish(writer, at: start + part.seconds)
            project.segments.append(.init(fileName: name, captureStart: start, duration: summary.duration, frames: summary.frames))
            offset += summary.duration
        }
        let activity = ActivityTrack(pixelWidth: width, pixelHeight: height, keyboardRecorded: true, clicks: clicks)
        return SampleRecording(folder: folder, project: project, activity: activity)
    }

    /// A 440 Hz tone whose loudness follows `amplitude` of the recording time, so each second can sound different.
    private static func tone(
        start: Double, firstFrame: Int, frames: Int, recordingOffset: Double, amplitude: (Double) -> Float
    ) -> CMSampleBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            let local = Double(firstFrame + frame) / 48_000
            buffer.floatChannelData![0][frame] = amplitude(recordingOffset + local) * Float(sin(local * 2 * .pi * 440))
        }
        return AudioNormalizer.sampleBuffer(from: buffer, at: RecordingMediaFactory.time(start + Double(firstFrame) / 48_000))!
    }

    private static func finish(_ writer: SegmentWriter, at end: TimeInterval) async throws -> SegmentWriter.Summary {
        try await withCheckedThrowingContinuation { continuation in
            writer.finish(endingAt: end) { continuation.resume(with: $0.mapError { $0 }) }
        }
    }

    func compose(_ options: RecordingComposition.Options = .init()) async throws -> RecordingComposition {
        try await RecordingComposition.make(project: project, folder: folder.url, activity: activity, options: options)
    }
}

/// What a composition delivers when it is read like the exporter reads it.
enum CompositionProbe {
    struct Frame {
        var time: Double
        var pixels: [PixelBuffers.Pixel]
    }

    /// Every frame of the video composition, with the pixels at `points` (output coordinates, origin at the top-left).
    static func frames(of built: RecordingComposition, at points: [(Int, Int)]) async throws -> [Frame] {
        let reader = try AVAssetReader(asset: built.composition)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [built.videoTrack], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.videoComposition = built.videoComposition
        reader.add(output)
        reader.startReading()
        var frames: [Frame] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            frames.append(Frame(
                time: sample.presentationTimeStamp.seconds, pixels: points.map { PixelBuffers.read(buffer, x: $0.0, y: $0.1) }
            ))
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        return frames
    }

    /// The sound of the composition as mono 48 kHz samples from time 0.
    static func samples(of built: RecordingComposition) async throws -> [Float] {
        guard !built.audioTracks.isEmpty else { return [] }
        let reader = try AVAssetReader(asset: built.composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: built.audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
        ])
        reader.add(output)
        reader.startReading()
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &chunk)
            samples += chunk
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        return samples
    }

    /// The root mean square of the samples between two times (seconds from the start).
    static func rms(_ samples: [Float], from start: Double, to end: Double) -> Double {
        let low = max(Int(start * 48_000), 0), high = min(Int(end * 48_000), samples.count)
        guard high > low else { return 0 }
        let sum = samples[low..<high].reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(high - low)).squareRoot()
    }
}
