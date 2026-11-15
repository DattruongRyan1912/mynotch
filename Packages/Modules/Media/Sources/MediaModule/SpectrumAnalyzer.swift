import Accelerate

/// Turns one frame of mono audio into a few loudness levels for the bars: Hann window, DFT, power per
/// log-spaced band in dB, scaled to 0…1 above a −60 dB floor, then smoothed so bars jump up and fall slowly.
/// A value type owned by the analysis queue; nothing here touches the main actor.
nonisolated struct SpectrumAnalyzer {
    static let lowestFrequency = 40.0
    static let highestFrequency = 16_000.0
    /// Band power at or below this reads as 0; a full-scale sine reads as 1.
    static let floorDecibels: Float = -60
    /// Share of the way to a louder level covered per call, so bars jump up with a beat…
    static let attack: Float = 0.6
    /// …and share of the way to a quieter one, so they fall back slowly.
    static let decay: Float = 0.15
    /// Levels below this (a tenth of a point of bar) snap to 0, so silence ends at exactly 0 within about
    /// a second instead of approaching it forever.
    static let restLevel: Float = 0.01

    let frameCount: Int
    let bandCount: Int
    let sampleRate: Double
    private let transform: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private let silence: [Float]
    /// DFT bins summed into each band, low to high.
    private let bandBins: [Range<Int>]
    private var levels: [Float]

    init(frameCount: Int = 1024, bandCount: Int, sampleRate: Double) {
        precondition(frameCount >= 16 && frameCount.nonzeroBitCount == 1, "frameCount must be a power of two")
        precondition(bandCount > 0 && sampleRate > 0, "bandCount and sampleRate must be positive")
        self.frameCount = frameCount
        self.bandCount = bandCount
        self.sampleRate = sampleRate
        // A power-of-two count is always a valid DFT length, so this cannot throw.
        transform = try! vDSP.DiscreteFourierTransform(
            count: frameCount, direction: .forward, transformType: .complexComplex, ofType: Float.self
        )
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: frameCount, isHalfWindow: false)
        silence = [Float](repeating: 0, count: frameCount)
        bandBins = Self.bandBins(frameCount: frameCount, bandCount: bandCount, sampleRate: sampleRate)
        levels = [Float](repeating: 0, count: bandCount)
    }

    /// Levels in 0…1 for `samples` (exactly `frameCount` mono samples), low to high frequencies.
    mutating func process(_ samples: [Float]) -> [Float] {
        precondition(samples.count == frameCount, "process expects \(frameCount) samples")
        var real = silence
        var imaginary = silence
        transform.transform(
            inputReal: vDSP.multiply(samples, window), inputImaginary: silence, outputReal: &real, outputImaginary: &imaginary
        )
        // The Hann window halves a sine's amplitude and the DFT sums N/2 of it, so 4/N brings full scale to 1.
        let scale = 4 / Float(frameCount)
        for (band, bins) in bandBins.enumerated() {
            var power: Float = 0
            for bin in bins { power += real[bin] * real[bin] + imaginary[bin] * imaginary[bin] }
            let decibels = 10 * log10(max(power * scale * scale, 1e-12))
            // A broken stream (NaN samples) reads as silence rather than poisoning the smoothed level for good.
            let target = decibels.isNaN ? 0 : min(max((decibels - Self.floorDecibels) / -Self.floorDecibels, 0), 1)
            let rate = target > levels[band] ? Self.attack : Self.decay
            let level = levels[band] + (target - levels[band]) * rate
            levels[band] = level < Self.restLevel ? 0 : level
        }
        return levels
    }

    /// Each band covers the bins from its lower edge up to the next band's; a band narrower than a bin
    /// still gets the nearest one, so no bar stays dead at low frequencies.
    private static func bandBins(frameCount: Int, bandCount: Int, sampleRate: Double) -> [Range<Int>] {
        let binWidth = sampleRate / Double(frameCount)
        let nyquistBin = frameCount / 2
        let ratio = highestFrequency / lowestFrequency
        func firstBin(ofBand band: Int) -> Int {
            Int((lowestFrequency * pow(ratio, Double(band) / Double(bandCount)) / binWidth).rounded(.up))
        }
        return (0..<bandCount).map { band in
            let lower = min(max(firstBin(ofBand: band), 1), nyquistBin - 1)
            let upper = min(max(firstBin(ofBand: band + 1), lower + 1), nyquistBin)
            return lower..<upper
        }
    }
}
