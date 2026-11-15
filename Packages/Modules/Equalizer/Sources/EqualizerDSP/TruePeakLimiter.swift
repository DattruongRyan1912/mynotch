import Foundation

/// Real-time Lookahead True-Peak Limiter conforming to ITU-R BS.1770-5 and EBU R128.
/// Uses 4x oversampling TruePeakDetector on a sidechain, a fixed lookahead FIFO delay line,
/// and linked stereo envelope follower with ~35ms hold and ~100ms release.
/// Guaranteed 0 heap allocations on the IO thread.
nonisolated public final class TruePeakLimiter: @unchecked Sendable {
    public let channelCount: Int
    public static let maxChannels = 8
    public static let maxCapacity = 2048 // Supports up to 192 kHz latency (396 frames) + margin
    public static let reserveDB: Double = 0.70 // Internal measurement margin for overloads conforming to ITU-R BS.1770-5 max FIR ripple

    private let detector: TruePeakDetector
    private var sampleRate: Double = 48_000.0
    private var latencyFrames: Int = 108

    // Circular audio FIFO for each channel
    private let fifo: UnsafeMutablePointer<Float>
    private var fifoWriteIndex: Int = 0

    // Limiter state
    private var ceilingDBTP: Double = -0.5
    private var ceilingLinear: Double = 0.9440608762859234
    private var thresholdLinear: Double = 0.8709635899458814 // (ceilingDBTP - 0.70 dB headroom for overloads)

    private var limiterEnvelope: Double = 0.9440608762859234
    private var limiterHoldRemaining: Int = 0
    private var limiterHoldFrames: Int = 1680 // ~35 ms at 48 kHz
    private var limiterReleaseDecay: Double = 0.99904144 // ~100 ms 99% decay at 48 kHz
    private var currentAppliedGain: Double = 1.0

    public init(channels: Int, sampleRate: Double = 48_000.0, ceilingDBTP: Double = -0.5) {
        channelCount = max(1, min(channels, Self.maxChannels))
        detector = TruePeakDetector(channels: channelCount)

        let totalFifo = channelCount * Self.maxCapacity
        fifo = .allocate(capacity: totalFifo)
        fifo.initialize(repeating: 0.0, count: totalFifo)

        updateTiming(sampleRate: sampleRate)
        updateCeiling(ceilingDBTP: ceilingDBTP)
    }

    deinit {
        fifo.deallocate()
    }

    public var latency: Int {
        latencyFrames
    }

    public var currentCeilingDBTP: Double {
        ceilingDBTP
    }

    public func updateTiming(sampleRate: Double) {
        let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000.0
        self.sampleRate = rate
        latencyFrames = min(Self.maxCapacity - 64, Int(ceil(0.002 * rate)) + TruePeakFIRCoefficients.tapsPerPhase)
        limiterHoldFrames = max(1, Int((0.035 * rate).rounded()))
        limiterReleaseDecay = exp(-4.605170185988091 / (0.100 * rate))
    }

    public func updateCeiling(ceilingDBTP: Double) {
        let db = ceilingDBTP.isFinite ? ceilingDBTP : -0.5
        self.ceilingDBTP = db
        self.ceilingLinear = pow(10.0, db / 20.0)
        self.thresholdLinear = pow(10.0, (db - Self.reserveDB) / 20.0)
        if limiterEnvelope < ceilingLinear {
            limiterEnvelope = ceilingLinear
        }
    }

    public func reset() {
        detector.reset()
        fifo.initialize(repeating: 0.0, count: channelCount * Self.maxCapacity)
        fifoWriteIndex = 0
        limiterEnvelope = 0.0
        limiterHoldRemaining = 0
        currentAppliedGain = 1.0
    }

    /// Resets the envelope follower and detector without clearing the audio delay line.
    /// Used when non-finite inputs occur to instantly restore clean unity gain.
    public func resetEnvelope() {
        detector.reset()
        limiterEnvelope = 0.0
        limiterHoldRemaining = 0
        currentAppliedGain = 1.0
    }

    /// Frame-by-frame processing across pre-gathered channel pointers.
    /// Input samples are processed through the TruePeak detector, delayed through FIFO,
    /// and output with zero overshoot and bit-exact preservation on clean signals.
    @inline(__always)
    public func processFrame(
        inputs: UnsafePointer<Double>,
        outputs: UnsafeMutablePointer<Float>,
        activeChannels: Int
    ) {
        let chCount = min(activeChannels, channelCount)

        // 1. Feed input samples into TruePeak detector & detect frame continuous peak
        var framePeak = 0.0
        var c = 0
        while c < chCount {
            let inSample = inputs[c]
            if inSample.isFinite {
                let peak = detector.processSample(channel: c, sample: inSample)
                if peak > framePeak {
                    framePeak = peak
                }
            }
            // Store incoming sample in circular FIFO
            fifo[c * Self.maxCapacity + fifoWriteIndex] = Float(inSample.isFinite ? inSample : 0.0)
            c += 1
        }

        // 2. Update Linked Envelope Follower with Lookahead Target
        if framePeak > limiterEnvelope {
            limiterEnvelope = framePeak
            limiterHoldRemaining = limiterHoldFrames
        } else if framePeak > ceilingLinear && framePeak >= limiterEnvelope * 0.85 {
            limiterHoldRemaining = limiterHoldFrames
        } else if limiterHoldRemaining > 0 {
            limiterHoldRemaining -= 1
        } else if limiterEnvelope > 0.0 {
            limiterEnvelope *= limiterReleaseDecay
            if limiterEnvelope < 0.00001 {
                limiterEnvelope = 0.0
            }
        }

        if !limiterEnvelope.isFinite {
            limiterEnvelope = 0.0
            limiterHoldRemaining = 0
        }

        // Calculate required target gain for the lookahead horizon
        let targetGain: Double
        if limiterEnvelope > ceilingLinear {
            targetGain = min(1.0, thresholdLinear / limiterEnvelope)
        } else {
            targetGain = 1.0
        }

        currentAppliedGain = targetGain

        // Read delayed sample from FIFO at (fifoWriteIndex - latencyFrames) using power-of-two bitwise mask
        let readIndex = (fifoWriteIndex - latencyFrames) & (Self.maxCapacity - 1)

        // 3. Apply gain to delayed sample and write to outputs
        let isSafeUnity = currentAppliedGain >= 0.99999
        let ceilLimit = Float(ceilingLinear)

        c = 0
        while c < chCount {
            let delayedVal = fifo[c * Self.maxCapacity + readIndex]
            if isSafeUnity && abs(delayedVal) <= ceilLimit {
                // Bit-exact preservation of safe samples
                outputs[c] = delayedVal
            } else {
                let scaled = Float(Double(delayedVal) * currentAppliedGain)
                outputs[c] = min(max(scaled, -ceilLimit), ceilLimit)
            }
            c += 1
        }

        // Advance circular pointer using power-of-two bitwise mask
        fifoWriteIndex = (fifoWriteIndex + 1) & (Self.maxCapacity - 1)
    }
}
