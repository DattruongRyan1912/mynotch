import Foundation
import Testing
@testable import MediaModule

@Suite struct SpectrumAnalyzerTests {
    static let frameCount = 1024

    /// One frame of the sum of sines at `frequencies`, each with `amplitude` (1 is full scale).
    static func sines(_ frequencies: [Double], amplitude: Float = 0.5, sampleRate: Double) -> [Float] {
        (0..<frameCount).map { index in
            let time = Double(index) / sampleRate
            return frequencies.reduce(Float(0)) { sum, frequency in sum + amplitude * Float(sin(2 * .pi * frequency * time)) }
        }
    }

    static let silence = [Float](repeating: 0, count: frameCount)

    /// Band a frequency falls in when `bandCount` log-spaced bands cover 40 Hz…16 kHz.
    static func band(of frequency: Double, bandCount: Int) -> Int {
        Int(log(frequency / 40) / log(16_000.0 / 40) * Double(bandCount))
    }

    /// Levels once the smoothing has settled on a steady input.
    static func settled(_ analyzer: inout SpectrumAnalyzer, on frame: [Float]) -> [Float] {
        var levels: [Float] = []
        for _ in 0..<40 { levels = analyzer.process(frame) }
        return levels
    }

    static func loudest(_ levels: [Float], count: Int) -> Set<Int> {
        Set(levels.indices.sorted { levels[$0] > levels[$1] }.prefix(count))
    }

    @Test(arguments: [(4, 44_100.0), (8, 48_000.0), (16, 48_000.0), (8, 96_000.0)])
    func sineAt1kHzPeaksInItsBand(bandCount: Int, sampleRate: Double) {
        var analyzer = SpectrumAnalyzer(bandCount: bandCount, sampleRate: sampleRate)
        let levels = Self.settled(&analyzer, on: Self.sines([1000], sampleRate: sampleRate))
        let peak = Self.band(of: 1000, bandCount: bandCount)
        #expect(Self.loudest(levels, count: 1) == [peak])
        #expect(levels[peak] > 0.8)
    }

    @Test func twoSinesPeakInTwoBands() {
        var analyzer = SpectrumAnalyzer(bandCount: 8, sampleRate: 48_000)
        let levels = Self.settled(&analyzer, on: Self.sines([280, 5000], sampleRate: 48_000))
        let low = Self.band(of: 280, bandCount: 8)
        let high = Self.band(of: 5000, bandCount: 8)
        #expect(low != high)
        #expect(Self.loudest(levels, count: 2) == [low, high])
        for band in levels.indices where band != low && band != high {
            #expect(levels[band] < min(levels[low], levels[high]) - 0.2)
        }
    }

    @Test func silenceGivesZeros() {
        var analyzer = SpectrumAnalyzer(bandCount: 4, sampleRate: 48_000)
        #expect(analyzer.process(Self.silence) == [0, 0, 0, 0])
    }

    @Test func silenceAfterMusicDecaysToZeros() {
        var analyzer = SpectrumAnalyzer(bandCount: 6, sampleRate: 48_000)
        let loud = Self.settled(&analyzer, on: Self.sines([66, 179, 486, 1318, 3578, 9712], amplitude: 0.3, sampleRate: 48_000))
        #expect(loud.allSatisfy { $0 > 0.3 })
        let decaying = analyzer.process(Self.silence)
        #expect(decaying.allSatisfy { $0 > 0 })
        let rest = Self.settled(&analyzer, on: Self.silence)
        #expect(rest == [Float](repeating: 0, count: 6))
    }

    /// Rising levels move 60 % of the way to the target per call, falling ones 15 %.
    @Test func smoothsWithFastAttackAndSlowDecay() {
        let frame = Self.sines([1000], sampleRate: 48_000)
        let band = Self.band(of: 1000, bandCount: 4)
        var reference = SpectrumAnalyzer(bandCount: 4, sampleRate: 48_000)
        let target = Self.settled(&reference, on: frame)[band]
        #expect(target > 0.8)

        var analyzer = SpectrumAnalyzer(bandCount: 4, sampleRate: 48_000)
        let first = analyzer.process(frame)[band]
        #expect(abs(first - 0.6 * target) < 0.001)
        let second = analyzer.process(frame)[band]
        #expect(abs(second - 0.84 * target) < 0.001)

        let settled = Self.settled(&analyzer, on: frame)[band]
        let falling = analyzer.process(Self.silence)[band]
        #expect(abs(falling - 0.85 * settled) < 0.001)
    }

    /// A sine of `decibels` dBFS has amplitude 10^(dB/20); its band power is that squared (plus up to 1.5x from
    /// the Hann window's neighbouring bins), so the level is (dB + 60) / 60 above the -60 dB floor: -40 dB is
    /// 1/3, up to 0.363 with the neighbours. 4/N→2/N, a -80 dB floor or a rectangular window all move it.
    @Test func absoluteLevelsFollowTheDecibelScale() {
        let band = Self.band(of: 1000, bandCount: 8)
        func level(atDecibels decibels: Double) -> Float {
            var analyzer = SpectrumAnalyzer(bandCount: 8, sampleRate: 48_000)
            let amplitude = Float(pow(10, decibels / 20))
            return Self.settled(&analyzer, on: Self.sines([1000], amplitude: amplitude, sampleRate: 48_000))[band]
        }
        #expect(abs(level(atDecibels: -40) - 0.36) < 0.05)
        #expect(abs(level(atDecibels: -60) - 0.03) < 0.03)
        #expect(level(atDecibels: -20) > 0.64 && level(atDecibels: -20) < 0.7)
    }

    /// The Hann window keeps a loud sine out of distant bands; a rectangular window would leak into them.
    @Test func aLoudSineDoesNotLeakIntoDistantBands() {
        var analyzer = SpectrumAnalyzer(bandCount: 16, sampleRate: 48_000)
        let levels = Self.settled(&analyzer, on: Self.sines([1000], amplitude: 0.5, sampleRate: 48_000))
        let peak = Self.band(of: 1000, bandCount: 16)
        for band in levels.indices where abs(band - peak) >= 3 {
            #expect(levels[band] < 0.02)
        }
    }

    @Test func brokenSamplesReadAsSilence() {
        var analyzer = SpectrumAnalyzer(bandCount: 4, sampleRate: 48_000)
        _ = Self.settled(&analyzer, on: Self.sines([1000], sampleRate: 48_000))
        let broken = [Float](repeating: .nan, count: Self.frameCount)
        #expect(analyzer.process(broken).allSatisfy { (0...1).contains($0) })
        #expect(Self.settled(&analyzer, on: broken) == [0, 0, 0, 0])
        #expect(Self.settled(&analyzer, on: Self.sines([1000], sampleRate: 48_000))[2] > 0.8)
    }

    @Test(arguments: [1, 4, 7, 32])
    func returnsOneLevelPerBandWithinZeroToOne(bandCount: Int) {
        var analyzer = SpectrumAnalyzer(bandCount: bandCount, sampleRate: 48_000)
        // Full-scale square wave: loud in every band, so clamping is exercised.
        let square = (0..<Self.frameCount).map { $0 % 64 < 32 ? Float(1) : -1 }
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<Self.frameCount).map { _ in Float.random(in: -1...1, using: &generator) }
        for frame in [square, noise, Self.silence, square] {
            let levels = analyzer.process(frame)
            #expect(levels.count == bandCount)
            #expect(levels.allSatisfy { (0...1).contains($0) })
        }
    }
}
