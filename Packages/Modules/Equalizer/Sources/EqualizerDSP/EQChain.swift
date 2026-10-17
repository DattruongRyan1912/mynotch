import CoreAudio
import Foundation
import Synchronization

/// Ten peaking bands and a preamp, run in place on the buffers of Core Audio's real-time IO thread.
///
/// Threads: `setParameters` may be called from any thread; `process` from one thread at a time (the IO thread).
/// `process` allocates nothing and takes no lock. It loops with `while` over raw pointers rather than `for … in` and
/// owns every byte it touches from `init`, the way `SampleRing` does.
nonisolated public final class EQChain: @unchecked Sendable {
    /// One octave wide: wide enough that ten bands overlap into a smooth curve (a plan choice).
    public static let q = 1.41
    public static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    /// What `setParameters` accepts for each band and for the preamp; anything else is clamped to it.
    public static let gainRange: ClosedRange<Double> = -12...12
    /// How long a change takes to cross over from the old settings to the new, in frames (5.3 ms at 48 kHz) and
    /// independent of the buffer size, which can be as small as 32 frames and as large as 4096.
    public static let rampFrames = 256

    private static let coefficientsPerBand = 5

    private let channelCount: Int
    private let bandCount: Int

    // Publishing: two slots written alternately, so the IO thread reads a finished set while the next one is written.
    // `published` is the generation of the newest finished set (it lives in slot `generation & 1`);
    // `beginning` is the newest generation a writer has started. A writer that starts generation g + 2 reuses the slot
    // a reader of g may still be copying, which the reader notices afterwards and then keeps what it had until the next buffer.
    private let slots: UnsafeMutablePointer<BiquadCoefficients>
    private let slotPreamps: UnsafeMutablePointer<Float>
    private let published = Atomic<UInt64>(0)
    private let beginning = Atomic<UInt64>(0)
    /// Serialises writers only. The IO thread never touches it.
    private let writers = Mutex<Void>(())

    // Everything below belongs to the IO thread.
    private var adopted: UInt64 = 0
    private let incoming: UnsafeMutablePointer<BiquadCoefficients>
    /// `bandCount × 5` values per array (b0, b1, b2, a1, a2): in use now, where the change is heading, the step per frame, and one frame's mix.
    private let current: UnsafeMutablePointer<Double>
    private let target: UnsafeMutablePointer<Double>
    private let step: UnsafeMutablePointer<Double>
    private let scratch: UnsafeMutablePointer<Double>
    /// Two filter states (z1, z2) per band per channel, kept in `Double`: a 32 Hz band's poles sit close to the unit circle.
    private let state: UnsafeMutablePointer<Double>
    /// Bands in the cascade: those the settings use, and those a ramp is still taking away.
    private let running: UnsafeMutablePointer<Bool>
    private let targetActive: UnsafeMutablePointer<Bool>
    private let activeBands: UnsafeMutablePointer<Int>
    private var activeCount = 0
    private var currentPreamp = 1.0
    private var targetPreamp = 1.0
    private var preampStep = 0.0
    private var rampRemaining = 0

    public init(channels: Int) {
        channelCount = max(1, channels)
        bandCount = Self.frequencies.count
        let bands = bandCount
        let values = bands * Self.coefficientsPerBand

        slots = .allocate(capacity: 2 * bands)
        slots.initialize(repeating: .identity, count: 2 * bands)
        slotPreamps = .allocate(capacity: 2)
        slotPreamps.initialize(repeating: 1, count: 2)
        incoming = .allocate(capacity: bands)
        incoming.initialize(repeating: .identity, count: bands)

        current = .allocate(capacity: values)
        target = .allocate(capacity: values)
        step = .allocate(capacity: values)
        scratch = .allocate(capacity: values)
        for pointer in [current, target, scratch] { Self.writeIdentity(to: pointer, bands: bands) }
        step.initialize(repeating: 0, count: values)

        state = .allocate(capacity: channelCount * bands * 2)
        state.initialize(repeating: 0, count: channelCount * bands * 2)
        running = .allocate(capacity: bands)
        running.initialize(repeating: false, count: bands)
        targetActive = .allocate(capacity: bands)
        targetActive.initialize(repeating: false, count: bands)
        activeBands = .allocate(capacity: bands)
        activeBands.initialize(repeating: 0, count: bands)
    }

    deinit {
        slots.deallocate()
        slotPreamps.deallocate()
        incoming.deallocate()
        current.deallocate()
        target.deallocate()
        step.deallocate()
        scratch.deallocate()
        state.deallocate()
        running.deallocate()
        targetActive.deallocate()
        activeBands.deallocate()
    }

    /// Takes new settings from any thread; the IO thread picks them up at the start of its next buffer and crosses over to them
    /// within `rampFrames`, so a slider drag or a profile switch makes no click. Each filter is computed here, never on the IO thread.
    ///
    /// A band at 0 dB is left out, and a profile that is flat all through (every band and the preamp at 0) is passed through bit for bit.
    /// Missing gains count as 0 and extra ones are ignored; a gain that is not a number counts as 0 and any gain is clamped to
    /// `gainRange`. A band that does not fit the sample rate (see `BiquadCoefficients.peaking`) is left out.
    public func setParameters(gains: [Double], preampDB: Double, sampleRate: Double) {
        var bands = [BiquadCoefficients]()
        bands.reserveCapacity(bandCount)
        for (index, frequency) in Self.frequencies.enumerated() {
            let gain = index < gains.count ? Self.sanitised(gains[index]) : 0
            bands.append(.peaking(frequency: frequency, gainDB: gain, q: Self.q, sampleRate: sampleRate))
        }
        let preamp = Float(pow(10, Self.sanitised(preampDB) / 20))
        writers.withLock { _ in
            let generation = published.load(ordering: .relaxed) + 1
            beginning.store(generation, ordering: .relaxed)
            atomicMemoryFence(ordering: .sequentiallyConsistent)
            let slot = Int(generation & 1)
            for (index, band) in bands.enumerated() { slots[slot * bandCount + index] = band }
            slotPreamps[slot] = preamp
            published.store(generation, ordering: .releasing)
        }
    }

    /// IO thread. Filters the buffers in place and keeps every sample within [-1, 1], so a +12 dB stack cannot drive the speakers past full scale.
    /// Takes one buffer of interleaved channels or one buffer per channel. Channels beyond the `channels` of `init` are left untouched.
    /// A sample that is not finite (a glitch upstream) comes out as 0 and resets that channel's filters, so it cannot ring on.
    /// Flat settings change nothing else: no clamp, no rounding.
    public func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard frames > 0 else { return }
        adoptPublishedParameters()
        var channel = 0
        var bufferIndex = 0
        while bufferIndex < buffers.count {
            let buffer = buffers[bufferIndex]
            bufferIndex += 1
            let width = Int(buffer.mNumberChannels)
            guard width > 0 else { continue }
            let firstChannel = channel
            channel += width
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self), firstChannel < channelCount else { continue }
            let available = min(frames, Int(buffer.mDataByteSize) / (width * MemoryLayout<Float>.size))
            var lane = 0
            while lane < width && firstChannel + lane < channelCount {
                processChannel(firstChannel + lane, data + lane, stride: width, frames: available)
                lane += 1
            }
        }
        advanceRamp(by: frames)
    }

    // MARK: Audio thread

    private func processChannel(_ channel: Int, _ data: UnsafeMutablePointer<Float>, stride: Int, frames: Int) {
        let channelState = state + channel * bandCount * 2
        var frame = 0
        if rampRemaining > 0 {
            let remaining = rampRemaining
            while frame < frames {
                var coefficients = target
                var preamp = targetPreamp
                if frame < remaining {
                    let progress = Double(frame + 1)
                    var index = 0
                    while index < activeCount {
                        let base = activeBands[index] * Self.coefficientsPerBand
                        var value = 0
                        while value < Self.coefficientsPerBand {
                            scratch[base + value] = current[base + value] + step[base + value] * progress
                            value += 1
                        }
                        index += 1
                    }
                    coefficients = scratch
                    preamp = currentPreamp + preampStep * progress
                }
                let sample = data + frame * stride
                sample.pointee = finish(cascade(Double(sample.pointee) * preamp, coefficients, channelState), channelState)
                frame += 1
            }
        } else if activeCount == 0 && targetPreamp == 1 {
            // Flat: leave the samples be, but never pass a glitch on to the speakers.
            while frame < frames {
                let sample = data + frame * stride
                if !sample.pointee.isFinite { sample.pointee = 0 }
                frame += 1
            }
        } else {
            while frame < frames {
                let sample = data + frame * stride
                sample.pointee = finish(cascade(Double(sample.pointee) * currentPreamp, current, channelState), channelState)
                frame += 1
            }
        }
    }

    /// Direct Form II transposed, one section after the other.
    @inline(__always)
    private func cascade(_ input: Double, _ coefficients: UnsafeMutablePointer<Double>, _ channelState: UnsafeMutablePointer<Double>) -> Double {
        var value = input
        var index = 0
        while index < activeCount {
            let band = activeBands[index]
            let c = coefficients + band * Self.coefficientsPerBand
            let z = channelState + band * 2
            let output = c[0] * value + z[0]
            z[0] = c[1] * value - c[3] * output + z[1]
            z[1] = c[2] * value - c[4] * output
            value = output
            index += 1
        }
        return value
    }

    @inline(__always)
    private func finish(_ value: Double, _ channelState: UnsafeMutablePointer<Double>) -> Float {
        guard value.isFinite else {
            clearState(channelState)
            return 0
        }
        return Float(value > 1 ? 1 : (value < -1 ? -1 : value))
    }

    private func clearState(_ channelState: UnsafeMutablePointer<Double>) {
        var index = 0
        while index < bandCount * 2 {
            channelState[index] = 0
            index += 1
        }
    }

    /// Takes the newest finished set the writers published, if any, and starts crossing over to it.
    private func adoptPublishedParameters() {
        let generation = published.load(ordering: .acquiring)
        guard generation != adopted else { return }
        let slot = Int(generation & 1)
        let preamp = slotPreamps[slot]
        var band = 0
        while band < bandCount {
            incoming[band] = slots[slot * bandCount + band]
            band += 1
        }
        atomicMemoryFence(ordering: .acquiring)
        // A writer already into generation + 2 may have rewritten this slot during the copy: keep the old settings and look again next buffer.
        guard beginning.load(ordering: .relaxed) < generation + 2 else { return }
        adopted = generation
        retarget(preamp: Double(preamp))
    }

    /// Aims at `incoming` from wherever the last change has got to (even halfway), so a change that comes while another is still
    /// crossing over bends from the filters in use now rather than jumping back to the old ones.
    private func retarget(preamp: Double) {
        var changed = preamp != targetPreamp
        var band = 0
        while band < bandCount {
            let c = incoming[band]
            let base = band * Self.coefficientsPerBand
            let values = (Double(c.b0), Double(c.b1), Double(c.b2), Double(c.a1), Double(c.a2))
            if target[base] != values.0 || target[base + 1] != values.1 || target[base + 2] != values.2
                || target[base + 3] != values.3 || target[base + 4] != values.4 {
                changed = true
            }
            target[base] = values.0
            target[base + 1] = values.1
            target[base + 2] = values.2
            target[base + 3] = values.3
            target[base + 4] = values.4
            targetActive[band] = c != .identity
            band += 1
        }
        guard changed else { return }
        targetPreamp = preamp
        let frames = Double(Self.rampFrames)
        band = 0
        while band < bandCount {
            let base = band * Self.coefficientsPerBand
            var value = 0
            while value < Self.coefficientsPerBand {
                step[base + value] = (target[base + value] - current[base + value]) / frames
                value += 1
            }
            running[band] = running[band] || targetActive[band]
            band += 1
        }
        preampStep = (targetPreamp - currentPreamp) / frames
        rampRemaining = Self.rampFrames
        rebuildActiveBands()
    }

    private func advanceRamp(by frames: Int) {
        guard rampRemaining > 0 else { return }
        guard frames < rampRemaining else {
            settle()
            return
        }
        var index = 0
        while index < activeCount {
            let base = activeBands[index] * Self.coefficientsPerBand
            var value = 0
            while value < Self.coefficientsPerBand {
                current[base + value] += step[base + value] * Double(frames)
                value += 1
            }
            index += 1
        }
        currentPreamp += preampStep * Double(frames)
        rampRemaining -= frames
    }

    /// The change has crossed over: land exactly on the target and drop the bands it no longer uses, with their state,
    /// so a band switched on again later starts clean.
    private func settle() {
        rampRemaining = 0
        var value = 0
        while value < bandCount * Self.coefficientsPerBand {
            current[value] = target[value]
            value += 1
        }
        currentPreamp = targetPreamp
        var band = 0
        while band < bandCount {
            if running[band] && !targetActive[band] {
                running[band] = false
                var channel = 0
                while channel < channelCount {
                    let z = state + (channel * bandCount + band) * 2
                    z[0] = 0
                    z[1] = 0
                    channel += 1
                }
            }
            band += 1
        }
        rebuildActiveBands()
    }

    private func rebuildActiveBands() {
        activeCount = 0
        var band = 0
        while band < bandCount {
            if running[band] {
                activeBands[activeCount] = band
                activeCount += 1
            }
            band += 1
        }
    }

    // MARK: Setup

    private static func sanitised(_ decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(max(decibels, gainRange.lowerBound), gainRange.upperBound)
    }

    private static func writeIdentity(to pointer: UnsafeMutablePointer<Double>, bands: Int) {
        for band in 0..<bands {
            let base = band * coefficientsPerBand
            pointer[base] = 1
            for value in 1..<coefficientsPerBand { pointer[base + value] = 0 }
        }
    }
}
