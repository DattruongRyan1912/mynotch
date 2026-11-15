import Testing
import CoreAudio
import Foundation
@testable import EqualizerDSP

@Suite("True-Peak Limiter Comprehensive Test Suite (B06 - B25)")
struct TruePeakLimiterTests {
    @Test("B06: Flat profile with inter-sample overload vector A=1.2 must limit continuous true peak <= ceiling across entire signal")
    func flatProfileLimitsIntersampleOverload() {
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48_000)

        let frameCount = 1024
        let inputSamples = TruePeakTestSignals.intersampleOverloadVector(frameCount: frameCount)
        let block = AudioBlock(channels: 1, frames: frameCount)
        block.load(inputSamples)

        chain.process(block.list, frames: frameCount)
        let outputSamples = block.samples()

        for s in outputSamples {
            #expect(s.isFinite)
        }

        let ceilingLinear = pow(10.0, EQChain.limiterCeilingDB / 20.0)
        let sampleMax = outputSamples.map { abs($0) }.max() ?? 0.0
        #expect(Double(sampleMax) <= ceilingLinear + 1e-6, "Sample peak must be <= ceilingLinear + 1e-6, got \(sampleMax)")

        let measuredDBTP = TruePeakReference.measureTruePeakDBTP(outputSamples, excludeTransientFrames: 0)
        #expect(measuredDBTP <= EQChain.limiterCeilingDB + 1e-6, "Continuous True-Peak must be clamped below ceiling: measured \(measuredDBTP) dBTP vs ceiling \(EQChain.limiterCeilingDB) dBTP")
        #expect(measuredDBTP >= EQChain.limiterCeilingDB - 1.2, "B07: True-Peak in steady state must retain useful level within range: measured \(measuredDBTP) dBTP")
    }

    @Test("B08: Normalized frequency and phase sweep protects against inter-sample peaks without overshoot")
    func normalizedFrequencyAndPhaseSweep() {
        let sampleRate = 48_000.0
        let ceilingLinear = pow(10.0, EQChain.limiterCeilingDB / 20.0)

        let freqs = [0.01, 0.05, 0.125, 1.0 / 6.0, 0.25, 0.375, 0.45, 0.49] // Normalized frequencies relative to Fs
        let phases = stride(from: 0.0, through: Double.pi - 1e-5, by: Double.pi / 12.0).map { $0 } // 15° steps across [0, pi)

        for normF in freqs {
            for phase in phases {
                let chain = EQChain(channels: 1)
                chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: sampleRate)
                let freq = normF * sampleRate
                let activeFrames = 512
                let flushFrames = 256
                let frameCount = activeFrames + flushFrames
                var samples = [Float]()
                samples.reserveCapacity(frameCount)
                for i in 0..<activeFrames {
                    let t = Double(i) / sampleRate
                    // Overload amplitude 1.25 with 32-sample cosine taper at boundaries per EBU Tech 3341
                    var amp = 1.25
                    if i < 32 {
                        amp *= 0.5 * (1.0 - cos(Double.pi * Double(i) / 32.0))
                    } else if i >= activeFrames - 32 {
                        let rem = Double(activeFrames - 1 - i)
                        amp *= 0.5 * (1.0 - cos(Double.pi * rem / 32.0))
                    }
                    samples.append(Float(amp * sin(2.0 * Double.pi * freq * t + phase)))
                }
                samples += Array(repeating: 0.0, count: flushFrames)

                let block = AudioBlock(channels: 1, frames: frameCount)
                block.load(samples)
                chain.process(block.list, frames: frameCount)
                let out = block.samples()

                let sampleMax = out.map { abs($0) }.max() ?? 0.0
                #expect(Double(sampleMax) <= ceilingLinear + 1e-6, "Freq \(freq) Hz sample peak must be <= ceiling: got \(sampleMax)")

                let measuredDBTP = TruePeakReference.measureTruePeakDBTP(out, excludeTransientFrames: 0)
                #expect(measuredDBTP <= EQChain.limiterCeilingDB + 1e-6, "Frequency \(freq) Hz, phase \(phase) must be limited <= ceiling: got \(measuredDBTP) dBTP")
            }
        }
    }

    @Test("B09: Transient at callback boundary is protected across partitions (32, 64, 128, 256, 1024)")
    func transientAtBufferBoundaryProtected() {
        let sampleRate = 48_000.0
        let ceilingLinear = pow(10.0, EQChain.limiterCeilingDB / 20.0)

        for partitionSize in [32, 64, 128, 256, 1024] {
            let chain = EQChain(channels: 1)
            chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: sampleRate)

            let totalFrames = 1024
            let input = TruePeakTestSignals.intersampleOverloadVector(frameCount: totalFrames)
            var output = [Float]()

            var offset = 0
            while offset < totalFrames {
                let chunkFrames = min(partitionSize, totalFrames - offset)
                let chunkInput = Array(input[offset..<(offset + chunkFrames)])
                let block = AudioBlock(channels: 1, frames: chunkFrames)
                block.load(chunkInput)

                chain.process(block.list, frames: chunkFrames)
                output.append(contentsOf: block.samples())
                offset += chunkFrames
            }

            // Flush remaining lookahead samples from FIFO
            let flushFrames = 256
            let flushBlock = AudioBlock(channels: 1, frames: flushFrames)
            flushBlock.load(Array(repeating: 0.0, count: flushFrames))
            chain.process(flushBlock.list, frames: flushFrames)
            output.append(contentsOf: flushBlock.samples())

            let sampleMax = output.map { abs($0) }.max() ?? 0.0
            #expect(Double(sampleMax) <= ceilingLinear + 1e-6, "Partition \(partitionSize) sample peak must be <= ceiling: got \(sampleMax)")

            let measuredDBTP = TruePeakReference.measureTruePeakDBTP(output, excludeTransientFrames: 0)
            #expect(measuredDBTP <= EQChain.limiterCeilingDB + 1e-6, "Partition size \(partitionSize) must protect inter-sample peak: got \(measuredDBTP) dBTP")
        }
    }

    @Test("B11: Extreme overdrive with +24 dB bands and +12 dB preamp remains strictly clamped")
    func extremeOverdriveBoostClamped() {
        let chain = EQChain(channels: 1)
        // Set all 10 bands to +24 dB and preamp to +12 dB
        chain.setParameters(gains: Array(repeating: 24.0, count: 10), preampDB: 12.0, sampleRate: 48_000, ceilingDBTP: -0.5)

        let activeFrames = 1024
        let flushFrames = 256
        let frameCount = activeFrames + flushFrames
        // Full-scale square-like input at 1 kHz with 32-sample boundary taper
        var samples = [Float]()
        samples.reserveCapacity(frameCount)
        for i in 0..<activeFrames {
            var amp = 0.95
            if i < 32 {
                amp *= 0.5 * (1.0 - cos(Double.pi * Double(i) / 32.0))
            } else if i >= activeFrames - 32 {
                let rem = Double(activeFrames - 1 - i)
                amp *= 0.5 * (1.0 - cos(Double.pi * rem / 32.0))
            }
            samples.append(Float(amp * ((i % 48 < 24) ? 1.0 : -1.0)))
        }
        samples += Array(repeating: 0.0, count: flushFrames)

        let block = AudioBlock(channels: 1, frames: frameCount)
        block.load(samples)

        chain.process(block.list, frames: frameCount)
        let output = block.samples()

        let ceilingLinear = pow(10.0, -0.5 / 20.0)
        let sampleMax = output.map { abs($0) }.max() ?? 0.0
        #expect(Double(sampleMax) <= ceilingLinear + 1e-6, "Sample peak under extreme overdrive must be <= ceiling: got \(sampleMax)")

        let measuredDBTP = TruePeakReference.measureTruePeakDBTP(output, excludeTransientFrames: 32)
        #expect(measuredDBTP <= -0.5 + 1e-6, "True-peak under extreme overdrive must be <= ceiling: got \(measuredDBTP) dBTP")

        for s in output {
            #expect(s.isFinite)
        }
    }

    @Test("B12: Dynamic ceiling update from 0.0 to -1.0 dBTP while processing")
    func dynamicCeilingUpdate() {
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48_000, ceilingDBTP: 0.0)

        let frameCount = 512
        let input = TruePeakTestSignals.intersampleOverloadVector(frameCount: frameCount)
        let block1 = AudioBlock(channels: 1, frames: frameCount)
        block1.load(input)
        chain.process(block1.list, frames: frameCount)

        // Lower ceiling to -1.0 dBTP
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48_000, ceilingDBTP: -1.0)

        let block2 = AudioBlock(channels: 1, frames: frameCount)
        block2.load(input)
        chain.process(block2.list, frames: frameCount)
        let output2 = block2.samples()

        let ceilingMinus1Linear = pow(10.0, -1.0 / 20.0)
        let sampleMax = output2.map { abs($0) }.max() ?? 0.0
        #expect(Double(sampleMax) <= ceilingMinus1Linear + 1e-6, "After changing ceiling to -1.0 dBTP, sample peak must be <= ceiling: got \(sampleMax)")

        let measuredDBTP = TruePeakReference.measureTruePeakDBTP(output2, excludeTransientFrames: 0)
        #expect(measuredDBTP <= -1.0 + 1e-6, "After changing ceiling to -1.0 dBTP, output must be <= -1.0 dBTP: got \(measuredDBTP) dBTP")
    }

    @Test("B13: Flat profile with safe signal preserves bit-exact values after fixed DSP lookahead latency")
    func flatProfilePreservesSafeSignalBitExactAfterLatency() {
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48_000)

        let expectedLatency = chain.latency
        let frameCount = 512
        let safeInput = TruePeakTestSignals.safeLowAmplitudeSine(frameCount: frameCount)
        let block = AudioBlock(channels: 1, frames: frameCount)
        block.load(safeInput)

        chain.process(block.list, frames: frameCount)
        let outputSamples = block.samples()

        var matchCount = 0
        for i in expectedLatency..<(frameCount - 32) {
            let inSample = safeInput[i - expectedLatency]
            let outSample = outputSamples[i]
            if inSample.bitPattern == outSample.bitPattern {
                matchCount += 1
            }
        }
        let testedCount = (frameCount - 32) - expectedLatency
        #expect(matchCount == testedCount, "Safe signal must match input bit-exactly after latency: matched \(matchCount)/\(testedCount)")
    }

    @Test("B14: Flat profile with loud over-unity samples [1.5, -2.0, 0.25, 1.0] must be clamped below ceiling")
    func flatProfileDoesNotPassThroughLoudOverUnitySamples() {
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48_000)

        let inputSamples = TruePeakTestSignals.loudOverUnitySamples + Array(repeating: Float(0.0), count: 256)
        let frameCount = inputSamples.count
        let block = AudioBlock(channels: 1, frames: frameCount)
        block.load(inputSamples)

        chain.process(block.list, frames: frameCount)
        let outputSamples = block.samples()

        let ceilingLinear = pow(10.0, EQChain.limiterCeilingDB / 20.0)
        let sampleMax = outputSamples.map { abs($0) }.max() ?? 0.0

        #expect(Double(sampleMax) <= ceilingLinear + 1e-6, "Loud over-unity samples must not pass through unattenuated: sampleMax was \(sampleMax)")
    }

    @Test("B16: Linked stereo limiter preserves channel ratio R = L / 4")
    func linkedStereoPreservesChannelRatio() {
        let chain = EQChain(channels: 2)
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48_000)

        let frameCount = 512
        var stereoSamples = [Float]()
        stereoSamples.reserveCapacity(frameCount * 2)

        // Channel 0 has overload signal, Channel 1 is Channel 0 / 4
        let monoInput = TruePeakTestSignals.intersampleOverloadVector(frameCount: frameCount)
        for s in monoInput {
            stereoSamples.append(s)
            stereoSamples.append(s * 0.25)
        }

        let block = AudioBlock(channels: 2, frames: frameCount, interleaved: true)
        block.load(stereoSamples)

        chain.process(block.list, frames: frameCount)
        let output = block.samples()

        // Check channel ratio L / R after latency
        let latency = chain.latency
        var ratioOkCount = 0
        var testedFrames = 0
        for frame in (latency + 16)..<(frameCount - 16) {
            let left = output[frame * 2]
            let right = output[frame * 2 + 1]
            if abs(left) > 0.1 {
                testedFrames += 1
                let ratio = right / left
                if abs(ratio - 0.25) <= 1e-5 {
                    ratioOkCount += 1
                }
            }
        }
        #expect(testedFrames > 50)
        #expect(ratioOkCount == testedFrames, "Stereo ratio must be strictly preserved: matched \(ratioOkCount)/\(testedFrames)")
    }

    @Test("B17: DSP Matrix across 6 sample rates, 3 ceilings, mono and stereo strictly clamps <= ceiling")
    func dspMatrixSweep() {
        let sampleRates = [16_000.0, 44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0]
        let ceilings = [-1.0, -0.5, 0.0]
        let channelConfigs = [1, 2]

        for sr in sampleRates {
            for ceilDB in ceilings {
                for ch in channelConfigs {
                    let chain = EQChain(channels: ch)
                    chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: sr, ceilingDBTP: ceilDB)
                    let ceilLinear = pow(10.0, ceilDB / 20.0)

                    let activeFrames = 512
                    let flushFrames = max(512, Int(ceil(0.002 * sr)) + 256)
                    let totalFrames = activeFrames + flushFrames

                    let activeInput = TruePeakTestSignals.intersampleOverloadVector(frameCount: activeFrames)
                    let block = AudioBlock(channels: ch, frames: totalFrames)

                    if ch == 1 {
                        var mono = activeInput
                        mono.append(contentsOf: Array(repeating: Float(0.0), count: flushFrames))
                        block.load(mono)
                    } else {
                        var stereo = [Float]()
                        stereo.reserveCapacity(totalFrames * 2)
                        for s in activeInput {
                            stereo.append(s)
                            stereo.append(s)
                        }
                        for _ in 0..<flushFrames {
                            stereo.append(0.0)
                            stereo.append(0.0)
                        }
                        block.load(stereo)
                    }

                    chain.process(block.list, frames: totalFrames)
                    let out = block.samples()

                    let sampleMax = out.map { abs($0) }.max() ?? 0.0
                    #expect(Double(sampleMax) <= ceilLinear + 1e-6, "SR \(sr), ceil \(ceilDB) dBTP, ch \(ch) sample peak failed: got \(sampleMax)")

                    if ch == 1 {
                        let measuredDBTP = TruePeakReference.measureTruePeakDBTP(out, excludeTransientFrames: 0)
                        #expect(measuredDBTP <= ceilDB + 1e-6, "SR \(sr), ceil \(ceilDB) dBTP, mono true-peak failed: got \(measuredDBTP) dBTP")
                    } else {
                        var left = [Float]()
                        var right = [Float]()
                        left.reserveCapacity(totalFrames)
                        right.reserveCapacity(totalFrames)
                        for i in 0..<totalFrames {
                            left.append(out[i * 2])
                            right.append(out[i * 2 + 1])
                        }
                        let leftDBTP = TruePeakReference.measureTruePeakDBTP(left, excludeTransientFrames: 0)
                        let rightDBTP = TruePeakReference.measureTruePeakDBTP(right, excludeTransientFrames: 0)
                        #expect(leftDBTP <= ceilDB + 1e-6, "SR \(sr), ceil \(ceilDB) dBTP, stereo L true-peak failed: got \(leftDBTP) dBTP")
                        #expect(rightDBTP <= ceilDB + 1e-6, "SR \(sr), ceil \(ceilDB) dBTP, stereo R true-peak failed: got \(rightDBTP) dBTP")
                    }
                }
            }
        }
    }

    @Test("B18: EBU Tech 3341 test signals (cases 15 to 23) protected through EQChain without overshoot")
    func ebuTech3341ProtectedThroughEQChain() {
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48_000, ceilingDBTP: -0.5)
        let ceilLinear = pow(10.0, -0.5 / 20.0)

        let cases: [([Float], String)] = [
            (TruePeakTestSignals.ebuCase15(frameCount: 512), "Case 15 (fs/4 0.50 FFS phase 0°)"),
            (TruePeakTestSignals.ebuCase16(frameCount: 512), "Case 16 (fs/4 0.50 FFS phase 45°)"),
            (TruePeakTestSignals.ebuCase17(frameCount: 512), "Case 17 (fs/6 0.50 FFS phase 60°)"),
            (TruePeakTestSignals.ebuCase18(frameCount: 512), "Case 18 (fs/8 0.50 FFS phase 67.5°)"),
            (TruePeakTestSignals.ebuCase19(frameCount: 512), "Case 19 (fs/4 1.414 FFS +3.0 dBTP)"),
            (TruePeakTestSignals.ebuCase20(frameCount: 512), "Case 20 (4x burst offset 0)"),
            (TruePeakTestSignals.ebuCase21(frameCount: 512), "Case 21 (4x burst offset 1)"),
            (TruePeakTestSignals.ebuCase22(frameCount: 512), "Case 22 (4x burst offset 2)"),
            (TruePeakTestSignals.ebuCase23(frameCount: 512), "Case 23 (4x burst offset 3)"),
        ]

        for (input, name) in cases {
            let flushFrames = 256
            let fullInput = input + Array(repeating: Float(0.0), count: flushFrames)
            let block = AudioBlock(channels: 1, frames: fullInput.count)
            block.load(fullInput)
            chain.process(block.list, frames: fullInput.count)
            let out = block.samples()

            let sampleMax = out.map { abs($0) }.max() ?? 0.0
            #expect(Double(sampleMax) <= ceilLinear + 1e-6, "\(name) sample peak failed: got \(sampleMax)")

            let measuredDBTP = TruePeakReference.measureTruePeakDBTP(out, excludeTransientFrames: 0)
            #expect(measuredDBTP <= -0.5 + 1e-6, "\(name) true-peak failed: got \(measuredDBTP) dBTP")
        }
    }

    @Test("B19: NaN transient does not reset envelope or allow queued FIFO overload to exceed ceiling")
    func nanTransientDoesNotDropLimiterGainForPendingFIFOSamples() {
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48_000.0, ceilingDBTP: -0.5)

        // 32 frames of overload A=1.2, 1 frame of NaN, followed by 128 frames of silence to flush FIFO
        var samples = TruePeakTestSignals.intersampleOverloadVector(frameCount: 32)
        samples.append(Float.nan)
        samples.append(contentsOf: Array(repeating: Float(0.0), count: 128))

        let block = AudioBlock(channels: 1, frames: samples.count)
        block.load(samples)
        chain.process(block.list, frames: samples.count)
        let out = block.samples()

        for s in out {
            #expect(s.isFinite, "Output must contain only finite samples")
        }

        let ceilingLinear = pow(10.0, -0.5 / 20.0)
        let sampleMax = out.map { abs($0) }.map { Double($0) }.max() ?? 0.0
        #expect(sampleMax <= ceilingLinear + 1e-6, "Sample peak after NaN must not exceed ceiling: \(sampleMax)")

        let measuredDBTP = TruePeakReference.measureTruePeakDBTP(out, excludeTransientFrames: 0)
        #expect(measuredDBTP <= -0.5 + 1e-6, "True-Peak after NaN must strictly clamp <= -0.5 dBTP, got \(measuredDBTP) dBTP")
    }

    @Test("B20: Codex Counterexample Regression - Fs/4 Sine A=0.9 with 480-frame taper is bit-exact preserved below -0.5 dBTP ceiling")
    func codexCounterexampleSineA09IsBitExactPreserved() {
        let chain = EQChain(channels: 1)
        chain.setParameters(gains: Array(repeating: 0.0, count: 10), preampDB: 0.0, sampleRate: 48_000.0, ceilingDBTP: -0.5)

        let activeFrames = 4096
        let latency = chain.latency // 108 frames
        let flushFrames = 256
        let totalFrames = activeFrames + flushFrames

        // Sine at Fs/4 (12 kHz at 48 kHz), amplitude 0.9 (-0.915 dBTP) with 480-frame raised cosine fade
        var input = [Float]()
        input.reserveCapacity(totalFrames)
        for i in 0..<activeFrames {
            var amp: Float = 0.90
            let fadeFrames = 480
            if i < fadeFrames {
                amp *= Float(0.5 * (1.0 - cos(Double.pi * Double(i) / Double(fadeFrames))))
            } else if i >= activeFrames - fadeFrames {
                let rem = Double(activeFrames - 1 - i)
                amp *= Float(0.5 * (1.0 - cos(Double.pi * rem / Double(fadeFrames))))
            }
            let phase = Double.pi * 0.5 * Double(i)
            input.append(amp * Float(sin(phase)))
        }
        input.append(contentsOf: Array(repeating: Float(0.0), count: flushFrames))

        // Measure input true-peak: must be -0.915 dBTP <= -0.5 dBTP (safe)
        let inTruePeak = TruePeakReference.measureTruePeakDBTP(input, excludeTransientFrames: 0)
        #expect(inTruePeak <= -0.5, "Input must be safe below ceiling, got \(inTruePeak) dBTP")

        let block = AudioBlock(channels: 1, frames: totalFrames)
        block.load(input)
        chain.process(block.list, frames: totalFrames)
        let output = block.samples()

        // 1. Output must not exceed ceiling
        let outTruePeak = TruePeakReference.measureTruePeakDBTP(output, excludeTransientFrames: 0)
        #expect(outTruePeak <= -0.5 + 1e-6, "Output must be <= ceiling, got \(outTruePeak) dBTP")

        // 2. Output startup frames must be bit-exact 0.0 silence
        for f in 0..<latency {
            #expect(output[f].bitPattern == Float(0.0).bitPattern, "Startup frame \(f) must be exact silence (0.0)")
        }

        // 3. ALL activeFrames (0..<4096) must be 100% BIT-EXACT identical to delayed input
        var bitExactCount = 0
        for i in 0..<activeFrames {
            let inBits = input[i].bitPattern
            let outBits = output[i + latency].bitPattern
            #expect(inBits == outBits, "Frame \(i) (output \(i + latency)) must have bit-exact pattern: in=\(input[i]) (\(inBits)), out=\(output[i + latency]) (\(outBits))")
            if inBits == outBits {
                bitExactCount += 1
            }
        }
        #expect(bitExactCount == activeFrames, "All \(activeFrames) frames must be bit-exact preserved (full signal)")
    }
}
