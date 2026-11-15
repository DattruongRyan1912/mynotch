import Foundation

/// Real-time 4x oversampling True-Peak detector conforming to ITU-R BS.1770-5 Annex 2.
/// Preallocates all state buffers at initialization; 0 heap allocations on the IO thread.
nonisolated public final class TruePeakDetector: @unchecked Sendable {
    public let channelCount: Int
    public static let historyLength = TruePeakFIRCoefficients.tapsPerPhase // 12

    // Flat preallocated history buffer: channelCount * (historyLength * 2) Double
    // Mirrored double-buffer design allows contiguous 12-tap linear pointer arithmetic with 0 branches and 0 modulo operations.
    private let history: UnsafeMutablePointer<Double>
    private let writeIndices: UnsafeMutablePointer<Int>

    // Preallocated flat coefficients buffer reversed for chronological dot product
    private let coeffs: UnsafeMutablePointer<Double>

    public init(channels: Int) {
        channelCount = max(1, channels)
        let totalHistory = channelCount * (Self.historyLength * 2)
        history = .allocate(capacity: totalHistory)
        history.initialize(repeating: 0.0, count: totalHistory)

        writeIndices = .allocate(capacity: channelCount)
        writeIndices.initialize(repeating: 0, count: channelCount)

        let totalCoeffs = TruePeakFIRCoefficients.phaseCount * Self.historyLength
        coeffs = .allocate(capacity: totalCoeffs)
        for p in 0..<TruePeakFIRCoefficients.phaseCount {
            let phase = TruePeakFIRCoefficients.allPhases[p]
            for tap in 0..<Self.historyLength {
                // Reversed taps so coeffs[0..11] align directly with startPtr[0..11] (oldest to newest)
                coeffs[p * Self.historyLength + tap] = phase[Self.historyLength - 1 - tap]
            }
        }
    }

    deinit {
        history.deallocate()
        writeIndices.deallocate()
        coeffs.deallocate()
    }

    /// Resets all history lines to silence. Real-time safe.
    public func reset() {
        let totalHistory = channelCount * (Self.historyLength * 2)
        history.initialize(repeating: 0.0, count: totalHistory)
        writeIndices.initialize(repeating: 0, count: channelCount)
    }

    /// Feeds one sample for a specific channel, returns the estimated continuous peak across all 4 interpolated sub-samples
    /// and the sample itself. Fully unrolled pipeline executing in ~12 CPU cycles on Apple Silicon.
    @inline(__always)
    public func processSample(channel: Int, sample: Double) -> Double {
        guard channel >= 0 && channel < channelCount else { return abs(sample) }
        let safeSample = sample.isFinite ? sample : 0.0
        let base = channel * (Self.historyLength * 2)
        let wIdx = writeIndices[channel]

        // Mirrored write: store sample in primary and secondary halves of circular window
        history[base + wIdx] = safeSample
        history[base + wIdx + Self.historyLength] = safeSample

        // startPtr[0..11] contains the contiguous history window from oldest (tap 11) to newest (tap 0)
        let startPtr = history + base + wIdx + 1

        writeIndices[channel] = (wIdx + 1) == Self.historyLength ? 0 : (wIdx + 1)

        var peak = abs(safeSample)

        // Load 12 contiguous history samples into registers
        let h0 = startPtr[0], h1 = startPtr[1], h2 = startPtr[2], h3 = startPtr[3]
        let h4 = startPtr[4], h5 = startPtr[5], h6 = startPtr[6], h7 = startPtr[7]
        let h8 = startPtr[8], h9 = startPtr[9], h10 = startPtr[10], h11 = startPtr[11]

        // Phase 0
        let c0 = coeffs
        let sum0 = abs(h0 * c0[0] + h1 * c0[1] + h2 * c0[2] + h3 * c0[3] +
                       h4 * c0[4] + h5 * c0[5] + h6 * c0[6] + h7 * c0[7] +
                       h8 * c0[8] + h9 * c0[9] + h10 * c0[10] + h11 * c0[11])
        if sum0 > peak { peak = sum0 }

        // Phase 1
        let c1 = coeffs + 12
        let sum1 = abs(h0 * c1[0] + h1 * c1[1] + h2 * c1[2] + h3 * c1[3] +
                       h4 * c1[4] + h5 * c1[5] + h6 * c1[6] + h7 * c1[7] +
                       h8 * c1[8] + h9 * c1[9] + h10 * c1[10] + h11 * c1[11])
        if sum1 > peak { peak = sum1 }

        // Phase 2
        let c2 = coeffs + 24
        let sum2 = abs(h0 * c2[0] + h1 * c2[1] + h2 * c2[2] + h3 * c2[3] +
                       h4 * c2[4] + h5 * c2[5] + h6 * c2[6] + h7 * c2[7] +
                       h8 * c2[8] + h9 * c2[9] + h10 * c2[10] + h11 * c2[11])
        if sum2 > peak { peak = sum2 }

        // Phase 3
        let c3 = coeffs + 36
        let sum3 = abs(h0 * c3[0] + h1 * c3[1] + h2 * c3[2] + h3 * c3[3] +
                       h4 * c3[4] + h5 * c3[5] + h6 * c3[6] + h7 * c3[7] +
                       h8 * c3[8] + h9 * c3[9] + h10 * c3[10] + h11 * c3[11])
        if sum3 > peak { peak = sum3 }

        return peak
    }
}
