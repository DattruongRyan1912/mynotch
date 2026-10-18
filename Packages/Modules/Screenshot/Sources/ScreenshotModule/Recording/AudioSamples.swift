import AVFoundation
import CoreMedia

/// Brings whatever audio arrives to the one format a track is written in: 48 kHz, 32-bit float, the track's channel count.
/// The writer is told that format once, so a microphone that delivers 44.1 kHz stereo, or a change of device in the middle of a
/// recording, cannot make a later buffer fail the whole file; and silence made to fill a gap always matches.
nonisolated final class AudioNormalizer {
    let format: AVAudioFormat
    private var converter: AVAudioConverter?
    private var converterSource: AVAudioFormat?

    init(kind: AudioTrackKind) {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Double(RecordingMedia.sampleRate),
            channels: AVAudioChannelCount(kind.channels), interleaved: false
        )!
    }

    /// `sample` in the track's format with the same start time; nil when it holds no audio or cannot be converted.
    func normalized(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample) else { return nil }
        let source = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0 else { return nil }
        if source == format { return sample }
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        input.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: input.mutableAudioBufferList) == noErr
        else { return nil }
        if converterSource != source {
            converter = AVAudioConverter(from: source, to: format)
            converterSource = source
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount((Double(frames) * format.sampleRate / source.sampleRate).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        // The block runs inside `convert`, on this thread, once per call.
        nonisolated(unsafe) var supplied = false
        nonisolated(unsafe) let pending = input
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return pending
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return Self.sampleBuffer(from: output, at: sample.presentationTimeStamp)
    }

    /// `seconds` of silence starting at `start`, in the track's format.
    func silence(from start: CMTime, seconds: TimeInterval) -> CMSampleBuffer? {
        let frames = AVAudioFrameCount((seconds * format.sampleRate).rounded())
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            buffer.floatChannelData?[channel].update(repeating: 0, count: Int(frames))
        }
        return Self.sampleBuffer(from: buffer, at: start)
    }

    /// A sample buffer holding a copy of `buffer`, whose first frame is at `time`.
    static func sampleBuffer(from buffer: AVAudioPCMBuffer, at time: CMTime) -> CMSampleBuffer? {
        let rate = Int32(buffer.format.sampleRate)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: rate), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: buffer.format.formatDescription, sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
        ) == noErr, let sample else { return nil }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
            bufferList: buffer.audioBufferList
        ) == noErr else { return nil }
        return sample
    }
}
