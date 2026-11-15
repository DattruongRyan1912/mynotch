import CoreAudio
import EqualizerDSP
import Foundation
import Synchronization

/// Where the tap's streams sit among the aggregate device's input streams, and how many streams it has.
///
/// The aggregate device lists the input streams of its sub-device first (a headset's microphone, say) and the tap's after them,
/// so the tap is found from the end. The channel counts are checked against what the tap and the device's output say,
/// so a guess that turns out wrong makes the build fail instead of replaying the wrong stream.
nonisolated struct StreamLayout: Equatable, Sendable {
    var firstInput: Int
    var streams: Int

    /// Each array holds the channel count of one stream, in order.
    static func resolve(tapChannels: Int, isInterleaved: Bool, inputStreams: [Int], outputStreams: [Int]) throws -> StreamLayout {
        guard tapChannels > 0 else { throw AudioSystemError("the tap has no channels") }
        let streams = isInterleaved ? 1 : tapChannels
        let channelsPerStream = isInterleaved ? tapChannels : 1
        guard inputStreams.count >= streams, outputStreams.count >= streams else {
            throw AudioSystemError("the device has fewer streams than the tap")
        }
        let layout = StreamLayout(firstInput: inputStreams.count - streams, streams: streams)
        for stream in 0..<streams {
            guard inputStreams[layout.firstInput + stream] == channelsPerStream, outputStreams[stream] == channelsPerStream else {
                throw AudioSystemError("the tap's channels do not match the device's streams")
            }
        }
        return layout
    }
}

/// The IO proc's work: copy the tap into the device's output, filter it, and note how loud the tap was.
///
/// Everything in `process` runs on Core Audio's real-time thread: no allocation, no locks, no actors, `while` loops only.
/// It stays silent until `open()`: the pipeline opens it once it knows MyNotch is left out of its own tap, because a replay
/// the tap can hear would feed back.
nonisolated final class PipelineIO: @unchecked Sendable {
    private let chain: EQChain
    private let layout: StreamLayout
    private let isOpen = Atomic<Bool>(false)
    /// The bits of a non-negative `Float`, which order like the numbers do.
    private let peakBits = Atomic<UInt32>(0)

    init(chain: EQChain, layout: StreamLayout) {
        self.chain = chain
        self.layout = layout
    }

    func open() {
        isOpen.store(true, ordering: .releasing)
    }

    /// The loudest tap sample since the last call, then starts counting again.
    func takePeak() -> Float {
        Float(bitPattern: peakBits.exchange(0, ordering: .relaxed))
    }

    func process(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let live = isOpen.load(ordering: .acquiring)
        var loudest: Float = 0
        var stream = 0
        while stream < outputs.count {
            let destination = outputs[stream]
            if let target = destination.mData {
                let capacity = Int(destination.mDataByteSize)
                var copied = 0
                if stream < layout.streams, layout.firstInput + stream < inputs.count {
                    let source = inputs[layout.firstInput + stream]
                    // A buffer that is not what the layout promised (a format that changed under us) is silence, never noise.
                    if let data = source.mData, source.mNumberChannels == destination.mNumberChannels {
                        let bytes = min(Int(source.mDataByteSize), capacity)
                        loudest = max(loudest, Self.peak(of: data, bytes: bytes))
                        if live {
                            memcpy(target, data, bytes)
                            copied = bytes
                        }
                    }
                }
                memset(target + copied, 0, capacity - copied)
            }
            stream += 1
        }
        if loudest > Float(bitPattern: peakBits.load(ordering: .relaxed)) {
            peakBits.store(loudest.bitPattern, ordering: .relaxed)
        }
        guard live, outputs.count > 0 else { return }
        let first = outputs[0]
        let width = Int(first.mNumberChannels) * MemoryLayout<Float>.size
        guard width > 0 else { return }
        chain.process(outputs, frames: Int(first.mDataByteSize) / width)
    }

    /// A sample that is not a number never counts as loud.
    private static func peak(of data: UnsafeMutableRawPointer, bytes: Int) -> Float {
        let samples = data.assumingMemoryBound(to: Float.self)
        let count = bytes / MemoryLayout<Float>.size
        var loudest: Float = 0
        var index = 0
        while index < count {
            let magnitude = abs(samples[index])
            if magnitude > loudest { loudest = magnitude }
            index += 1
        }
        return loudest
    }
}
