import CoreAudio
import Synchronization

/// Hands audio from Core Audio's real-time IO thread to the analysis queue without locks or allocation:
/// the IO thread mixes each cycle to mono into preallocated storage, then publishes the new sample count.
/// Exactly one writer (the IO thread) and one reader (the analysis queue).
nonisolated final class SampleRing: @unchecked Sendable {
    let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    /// Samples written so far; sample `n` lives at `n % capacity` until `n + capacity` overwrites it.
    private let written = Atomic<Int>(0)

    init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit { storage.deallocate() }

    var writtenCount: Int { written.load(ordering: .acquiring) }

    /// IO thread: appends the mono mix of one cycle of 32-bit float PCM, interleaved or one buffer per channel.
    /// Streams without data (disabled by the device) are left out of the mix.
    func write(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        var channelCount = 0
        var frameCount = Int.max
        for buffer in buffers where buffer.mData != nil && buffer.mNumberChannels > 0 {
            let channels = Int(buffer.mNumberChannels)
            channelCount += channels
            frameCount = min(frameCount, Int(buffer.mDataByteSize) / (channels * MemoryLayout<Float>.size))
        }
        guard channelCount > 0, frameCount > 0 else { return }
        let start = written.load(ordering: .relaxed)
        let scale = 1 / Float(channelCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let channels = Int(buffer.mNumberChannels)
                for channel in 0..<channels { sum += data[frame * channels + channel] }
            }
            storage[(start + frame) % capacity] = sum * scale
        }
        written.store(start + frameCount, ordering: .releasing)
    }

    /// Reader: fills `frame` with the latest `frame.count` samples and returns the written count they end at;
    /// nil when fewer were written, or when the writer may have overwritten some of them during the copy.
    func copyLatest(into frame: inout [Float]) -> Int? {
        let count = frame.count
        let end = written.load(ordering: .acquiring)
        guard count < capacity, end >= count else { return nil }
        frame.withUnsafeMutableBufferPointer { destination in
            for index in 0..<count { destination[index] = storage[(end - count + index) % capacity] }
        }
        // The writer fills slots past `written` before publishing them, so keep half the free space as a margin
        // for a cycle in progress: a copy only counts when the writer is still well short of lapping it.
        atomicMemoryFence(ordering: .acquiring)
        guard written.load(ordering: .relaxed) - end < (capacity - count) / 2 else { return nil }
        return end
    }
}
