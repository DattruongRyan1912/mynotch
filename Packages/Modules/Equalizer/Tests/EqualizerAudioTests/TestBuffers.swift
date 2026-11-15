import CoreAudio
import EqualizerDSP
import Foundation

/// An `AudioBufferList` of floats that the test owns, standing in for the one Core Audio hands the IO block.
nonisolated final class TestBufferList {
    struct Spec {
        var channels: Int
        /// nil gives a buffer with no data, which is what a stream that is switched off looks like.
        var frames: Int?
    }

    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>?] = []

    init(_ specs: [Spec]) {
        list = AudioBufferList.allocate(maximumBuffers: max(1, specs.count))
        list.count = specs.count
        for (index, spec) in specs.enumerated() {
            guard let frames = spec.frames else {
                list[index] = AudioBuffer(mNumberChannels: UInt32(spec.channels), mDataByteSize: 0, mData: nil)
                storage.append(nil)
                continue
            }
            let count = spec.channels * frames
            let data = UnsafeMutablePointer<Float>.allocate(capacity: max(1, count))
            data.initialize(repeating: 0, count: max(1, count))
            list[index] = AudioBuffer(mNumberChannels: UInt32(spec.channels), mDataByteSize: UInt32(count * 4), mData: data)
            storage.append(data)
        }
    }

    deinit {
        for data in storage { data?.deallocate() }
        list.unsafeMutablePointer.deallocate()
    }

    func fill(_ index: Int, with values: [Float]) {
        for (offset, value) in values.enumerated() { storage[index]![offset] = value }
    }

    func samples(_ index: Int) -> [Float] {
        guard let data = storage[index] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(list[index].mDataByteSize) / 4))
    }
}

/// Runs a sine through `chain` for a few buffers and returns the last one, so a test can see what the chain was told to do.
nonisolated func render(_ chain: EQChain, frequency: Double = 1000, sampleRate: Double = 48_000, buffers: Int = 4) -> [Float] {
    let frames = 512
    let buffer = TestBufferList([.init(channels: 1, frames: frames)])
    var position = 0
    for _ in 0..<buffers {
        let samples = (0..<frames).map { Float(0.5 * sin(2 * Double.pi * frequency * Double(position + $0) / sampleRate)) }
        buffer.fill(0, with: samples)
        chain.process(buffer.list, frames: frames)
        position += frames
    }
    return buffer.samples(0)
}
