import CoreAudio
import Foundation
import Testing
@testable import MediaModule

@Suite struct SampleRingTests {
    /// Calls `body` with an AudioBufferList whose buffers hold `channels` (each buffer interleaves its own channels).
    static func withBufferList(_ channels: [[[Float]]], _ body: (UnsafePointer<AudioBufferList>) -> Void) {
        let list = AudioBufferList.allocate(maximumBuffers: channels.count)
        defer { free(list.unsafeMutablePointer) }
        var storage: [UnsafeMutablePointer<Float>] = []
        defer { storage.forEach { $0.deallocate() } }
        for (index, bufferChannels) in channels.enumerated() {
            let frames = bufferChannels.first?.count ?? 0
            let samples = (0..<frames).flatMap { frame in bufferChannels.map { $0[frame] } }
            let data = UnsafeMutablePointer<Float>.allocate(capacity: max(samples.count, 1))
            data.initialize(from: samples, count: samples.count)
            storage.append(data)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(bufferChannels.count),
                mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.size),
                mData: data
            )
        }
        body(list.unsafePointer)
    }

    func latest(_ ring: SampleRing, count: Int) -> [Float]? {
        var frame = [Float](repeating: .nan, count: count)
        return ring.copyLatest(into: &frame) == nil ? nil : frame
    }

    @Test func mixesInterleavedStereoToMono() {
        let ring = SampleRing(capacity: 16)
        Self.withBufferList([[[1, 0.5, 0], [0, 0.5, -1]]]) { ring.write($0) }
        #expect(latest(ring, count: 3) == [0.5, 0.5, -0.5])
        #expect(ring.writtenCount == 3)
    }

    @Test func mixesSeparateChannelBuffersToMono() {
        let ring = SampleRing(capacity: 16)
        Self.withBufferList([[[1, 1]], [[0, -1]]]) { ring.write($0) }
        #expect(latest(ring, count: 2) == [0.5, 0])
    }

    @Test func skipsDisabledStreams() {
        let ring = SampleRing(capacity: 16)
        Self.withBufferList([[[0.25, 0.75]]]) { list in
            let copy = AudioBufferList.allocate(maximumBuffers: 2)
            defer { free(copy.unsafeMutablePointer) }
            copy[0] = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))[0]
            copy[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: nil)
            ring.write(copy.unsafePointer)
        }
        #expect(latest(ring, count: 2) == [0.25, 0.75])
    }

    @Test func returnsTheLatestSamplesAcrossTheWrap() {
        let ring = SampleRing(capacity: 8)
        for chunk in stride(from: 0, to: 20, by: 3) {
            Self.withBufferList([[(chunk..<chunk + 3).map(Float.init)]]) { ring.write($0) }
        }
        #expect(ring.writtenCount == 21)
        #expect(latest(ring, count: 5) == [16, 17, 18, 19, 20])
    }

    @Test func needsEnoughSamples() {
        let ring = SampleRing(capacity: 8)
        #expect(latest(ring, count: 1) == nil)
        Self.withBufferList([[[1, 2]]]) { ring.write($0) }
        #expect(latest(ring, count: 3) == nil)
        #expect(latest(ring, count: 2) == [1, 2])
        // More than the ring holds can never be a consistent copy.
        Self.withBufferList([[(0..<10).map(Float.init)]]) { ring.write($0) }
        #expect(latest(ring, count: 9) == nil)
    }
}
