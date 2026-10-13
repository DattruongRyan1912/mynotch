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
        var index = 0
        while index < buffers.count {
            let buffer = buffers[index]
            index += 1
            guard buffer.mData != nil, buffer.mNumberChannels > 0 else { continue }
            let channels = Int(buffer.mNumberChannels)
            channelCount += channels
            frameCount = min(frameCount, Int(buffer.mDataByteSize) / (channels * MemoryLayout<Float>.size))
        }
        guard channelCount > 0, frameCount > 0 else { return }
        let start = written.load(ordering: .relaxed)
        let scale = 1 / Float(channelCount)
        // `while` rather than `for … in 0..<n`: at -Onone the range iterators allocate, and this runs on the IO thread.
        var frame = 0
        while frame < frameCount {
            var sum: Float = 0
            var bufferIndex = 0
            while bufferIndex < buffers.count {
                let buffer = buffers[bufferIndex]
                bufferIndex += 1
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let channels = Int(buffer.mNumberChannels)
                var channel = 0
                while channel < channels {
                    sum += data[frame * channels + channel]
                    channel += 1
                }
            }
            storage[(start + frame) % capacity] = sum * scale
            frame += 1
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
            // Plain loads are intended: one producer, aligned `Float`s, ordered by the fence below.
            for index in 0..<count { destination[index] = storage[(end - count + index) % capacity] }
        }
        // The writer fills slots past `written` before publishing them, so keep half the free space as a margin
        // for a cycle in progress: a copy only counts when the writer is still well short of lapping it.
        atomicMemoryFence(ordering: .acquiring)
        guard written.load(ordering: .relaxed) - end < (capacity - count) / 2 else { return nil }
        return end
    }
}
