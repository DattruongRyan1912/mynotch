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
    /// What `setParameters` accepts for each band; anything else is clamped to it.
    public static let gainRange: ClosedRange<Double> = -24...24
    /// What `setParameters` accepts for the preamp; anything else is clamped to it.
    public static let preampRange: ClosedRange<Double> = -12...12
    /// Headroom attenuation range for automatic headroom calculation (-48 dB to 0 dB).
    public static let headroomRange: ClosedRange<Double> = -48...0
    /// How long a change takes to cross over from the old settings to the new, in frames (5.3 ms at 48 kHz) and
    /// independent of the buffer size, which can be as small as 32 frames and as large as 4096.
    public static let rampFrames = 256

    /// True-Peak Limiter Ceiling (-0.5 dBFS) for ITU-R BS.1770 and Bluetooth AAC/SBC codec protection
    public static let limiterCeilingDB: Double = -0.5
    public static let limiterCeiling: Double = 0.9440608762859234 // pow(10.0, -0.5 / 20.0)
    public static let softKneeStart: Double = limiterCeiling
    public static let limiterThreshold: Double = limiterCeiling
    public static let limiterMinGain: Double = 0.0

    private static let coefficientsPerBand = 5

    public let channelCount: Int
    private let bandCount: Int

    // Publishing: two slots written alternately, so the IO thread reads a finished set while the next one is written.
    private let slots: UnsafeMutablePointer<BiquadCoefficients>
    private let slotPreamps: UnsafeMutablePointer<Double>
    private let slotSampleRates: UnsafeMutablePointer<Double>
    private let slotCeilings: UnsafeMutablePointer<Double>
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

    // Pre-allocated scratch buffers for frame-major IO processing (0 allocations on IO thread)
    private let channelPtrs: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    private let channelStrides: UnsafeMutablePointer<Int>
    private let channelFrames: UnsafeMutablePointer<Int>
    private let frameSamples: UnsafeMutablePointer<Double>
    private let limiterFrameOut: UnsafeMutablePointer<Float>
    private let channelFinite: UnsafeMutablePointer<Bool>

    // True-Peak Lookahead Limiter (4x oversampling polyphase FIR per ITU-R BS.1770-5 Annex 2)
    private let truePeakLimiter: TruePeakLimiter
    private var nonFiniteRunCount = 0

    public init(channels: Int) {
        channelCount = max(1, channels)
        bandCount = Self.frequencies.count
        let bands = bandCount
        let values = bands * Self.coefficientsPerBand

        slots = .allocate(capacity: 2 * bands)
        slots.initialize(repeating: .identity, count: 2 * bands)
        slotPreamps = .allocate(capacity: 2)
        slotPreamps.initialize(repeating: 1.0, count: 2)
        slotSampleRates = .allocate(capacity: 2)
        slotSampleRates.initialize(repeating: 48_000, count: 2)
        slotCeilings = .allocate(capacity: 2)
        slotCeilings.initialize(repeating: Self.limiterCeilingDB, count: 2)
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

        channelPtrs = .allocate(capacity: channelCount)
        channelPtrs.initialize(repeating: nil, count: channelCount)
        channelStrides = .allocate(capacity: channelCount)
        channelStrides.initialize(repeating: 1, count: channelCount)
        channelFrames = .allocate(capacity: channelCount)
        channelFrames.initialize(repeating: 0, count: channelCount)
        frameSamples = .allocate(capacity: channelCount)
        frameSamples.initialize(repeating: 0.0, count: channelCount)
        limiterFrameOut = .allocate(capacity: channelCount)
        limiterFrameOut.initialize(repeating: 0.0, count: channelCount)
        channelFinite = .allocate(capacity: channelCount)
        channelFinite.initialize(repeating: true, count: channelCount)

        truePeakLimiter = TruePeakLimiter(channels: channelCount, sampleRate: 48_000, ceilingDBTP: Self.limiterCeilingDB)
    }

    deinit {
        slots.deallocate()
        slotPreamps.deallocate()
        slotSampleRates.deallocate()
        slotCeilings.deallocate()
        incoming.deallocate()
        current.deallocate()
        target.deallocate()
        step.deallocate()
        scratch.deallocate()
        state.deallocate()
        running.deallocate()
        targetActive.deallocate()
        activeBands.deallocate()
        channelPtrs.deallocate()
        channelStrides.deallocate()
        channelFrames.deallocate()
        frameSamples.deallocate()
        limiterFrameOut.deallocate()
        channelFinite.deallocate()
    }

    /// Latency in frames introduced by the True-Peak lookahead filter.
    public var latency: Int {
        truePeakLimiter.latency
    }

    /// Publishes prepared biquad coefficients (e.g. from Apple AUNBandEQ) and effective preamp atomically.
    public func setCoefficients(_ coefficients: [BiquadCoefficients], preampDB: Double, sampleRate: Double = 48_000, ceilingDBTP: Double = limiterCeilingDB, headroomDB: Double = 0) {
        var bands = [BiquadCoefficients]()
        bands.reserveCapacity(bandCount)
        for index in 0..<bandCount {
            if index < coefficients.count {
                bands.append(coefficients[index])
            } else {
                bands.append(.identity)
            }
        }
        let safePreampDB = Self.sanitisedPreamp(preampDB)
        let safeHeadroomDB = Self.sanitisedHeadroom(headroomDB)
        let totalGainDB = safePreampDB + safeHeadroomDB
        let preamp = pow(10, totalGainDB / 20)
        let safeRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        let safeCeiling = ceilingDBTP.isFinite ? ceilingDBTP : Self.limiterCeilingDB
        writers.withLock { _ in
            let generation = published.load(ordering: .relaxed) + 1
            beginning.store(generation, ordering: .relaxed)
            atomicMemoryFence(ordering: .sequentiallyConsistent)
            let slot = Int(generation & 1)
            for (index, band) in bands.enumerated() { slots[slot * bandCount + index] = band }
            slotPreamps[slot] = preamp
            slotSampleRates[slot] = safeRate
            slotCeilings[slot] = safeCeiling
            published.store(generation, ordering: .releasing)
        }
    }

    /// Takes new settings from any thread; the IO thread picks them up at the start of its next buffer and crosses over to them
    /// within `rampFrames`, so a slider drag or a profile switch makes no click. Each filter is computed here, never on the IO thread.
    public func setParameters(gains: [Double], preampDB: Double, sampleRate: Double, ceilingDBTP: Double = limiterCeilingDB) {
        var bands = [BiquadCoefficients]()
        bands.reserveCapacity(bandCount)
        for (index, frequency) in Self.frequencies.enumerated() {
            let gain = index < gains.count ? Self.sanitised(gains[index]) : 0
            bands.append(.peaking(frequency: frequency, gainDB: gain, q: Self.q, sampleRate: sampleRate))
        }
        setCoefficients(bands, preampDB: Self.sanitisedPreamp(preampDB), sampleRate: sampleRate, ceilingDBTP: ceilingDBTP)
    }

    /// IO thread. Filters the buffers in place and keeps every sample within [-1, 1], preserving stereo balance
    /// and preventing overload with a linked stereo envelope follower.
    public func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard frames > 0 else { return }
        adoptPublishedParameters()

        // 1. Gather all available channels into scratch pointers
        var channelIndex = 0
        var bufferIndex = 0
        while bufferIndex < buffers.count && channelIndex < channelCount {
            let buffer = buffers[bufferIndex]
            bufferIndex += 1
            let width = Int(buffer.mNumberChannels)
            guard width > 0 else { continue }
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                var lane = 0
                while lane < width && channelIndex < channelCount {
                    channelPtrs[channelIndex] = nil
                    channelFrames[channelIndex] = 0
                    channelIndex += 1
                    lane += 1
                }
                continue
            }
            let available = min(frames, Int(buffer.mDataByteSize) / (width * MemoryLayout<Float>.size))
            var lane = 0
            while lane < width && channelIndex < channelCount {
                channelPtrs[channelIndex] = data + lane
                channelStrides[channelIndex] = width
                channelFrames[channelIndex] = available
                channelIndex += 1
                lane += 1
            }
        }
        let totalActiveChannels = channelIndex
        guard totalActiveChannels > 0 else {
            advanceRamp(by: frames)
            return
        }

        // 2. Main frame-major loop: process all channels frame by frame with TruePeakLimiter
        let isCascadeActive = activeCount > 0 || currentPreamp != 1 || rampRemaining > 0
        var frame = 0
        let remaining = rampRemaining
        while frame < frames {
            var coefficients = target
            var preamp = targetPreamp
            if remaining > 0 {
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
            } else {
                coefficients = current
                preamp = currentPreamp
            }

            var hasActiveData = false
            var anyActiveDataFinite = false
            var c = 0
            while c < totalActiveChannels {
                if frame < channelFrames[c], let basePtr = channelPtrs[c] {
                    hasActiveData = true
                    let samplePtr = basePtr + frame * channelStrides[c]
                    let inVal = Double(samplePtr.pointee)
                    let chState = state + c * bandCount * 2
                    if !inVal.isFinite {
                        clearState(c, chState)
                        frameSamples[c] = 0.0
                        channelFinite[c] = false
                    } else if isCascadeActive {
                        let filtered = cascade(inVal * preamp, coefficients, chState)
                        if !filtered.isFinite {
                            clearState(c, chState)
                            frameSamples[c] = 0.0
                            channelFinite[c] = false
                        } else {
                            frameSamples[c] = filtered
                            channelFinite[c] = true
                            anyActiveDataFinite = true
                        }
                    } else {
                        frameSamples[c] = inVal
                        channelFinite[c] = true
                        anyActiveDataFinite = true
                    }
                } else {
                    frameSamples[c] = 0.0
                    channelFinite[c] = true
                }
                c += 1
            }

            if hasActiveData && !anyActiveDataFinite {
                nonFiniteRunCount += 1
                if nonFiniteRunCount >= truePeakLimiter.latency {
                    truePeakLimiter.resetEnvelope()
                }
            } else if anyActiveDataFinite {
                nonFiniteRunCount = 0
            }

            // Feed frame into TruePeakLimiter and write delayed & limited output
            truePeakLimiter.processFrame(
                inputs: frameSamples,
                outputs: limiterFrameOut,
                activeChannels: totalActiveChannels
            )

            c = 0
            while c < totalActiveChannels {
                if frame < channelFrames[c], let basePtr = channelPtrs[c] {
                    let samplePtr = basePtr + frame * channelStrides[c]
                    // Write the delayed, sanitized and limited sample from TruePeakLimiter
                    samplePtr.pointee = limiterFrameOut[c]
                }
                c += 1
            }

            frame += 1
        }

        advanceRamp(by: frames)
    }

    // MARK: Audio thread

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
    public static func softSaturate(_ value: Double) -> Double {
        min(max(value, -limiterCeiling), limiterCeiling)
    }

    private func clearState(_ channel: Int, _ channelState: UnsafeMutablePointer<Double>) {
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
        let sampleRate = slotSampleRates[slot]
        let ceiling = slotCeilings[slot]
        var band = 0
        while band < bandCount {
            incoming[band] = slots[slot * bandCount + band]
            band += 1
        }
        atomicMemoryFence(ordering: .acquiring)
        guard beginning.load(ordering: .relaxed) < generation + 2 else { return }
        adopted = generation
        retarget(preamp: preamp, sampleRate: sampleRate, ceilingDBTP: ceiling)
    }

    private func retarget(preamp: Double, sampleRate: Double, ceilingDBTP: Double) {
        truePeakLimiter.updateTiming(sampleRate: sampleRate)
        truePeakLimiter.updateCeiling(ceilingDBTP: ceilingDBTP)
        var changed = preamp != targetPreamp
        var band = 0
        while band < bandCount {
            let c = incoming[band]
            let base = band * Self.coefficientsPerBand
            let values = (c.b0, c.b1, c.b2, c.a1, c.a2)
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

    private static func sanitisedPreamp(_ decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(max(decibels, preampRange.lowerBound), preampRange.upperBound)
    }

    private static func sanitisedHeadroom(_ decibels: Double) -> Double {
        guard decibels.isFinite, decibels <= 0 else { return 0 }
        return min(max(decibels, headroomRange.lowerBound), headroomRange.upperBound)
    }

    private static func writeIdentity(to pointer: UnsafeMutablePointer<Double>, bands: Int) {
        for band in 0..<bands {
            let base = band * coefficientsPerBand
            pointer[base] = 1
            for value in 1..<coefficientsPerBand { pointer[base + value] = 0 }
        }
    }
}
