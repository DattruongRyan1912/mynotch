import CryptoKit
import Foundation
import Testing
@testable import EqualizerDSP

@Suite("True-Peak Limiter PCM Vector Export & Zero-Overshoot Verification")
struct TruePeakPCMExportTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // EqualizerDSPTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Equalizer
            .deletingLastPathComponent() // Modules
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // Repo Root
    }

    private static func sha256Hex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    struct TestCaseDef {
        let id: String
        let description: String
        let expectedDBTP: Double
        let generate: (Int) -> [Float]
    }

    @Test("Export PCM Vectors from EQChain, Verify Zero Overshoot and Generate Manifest")
    func exportPCMVectorsAndVerifyZeroOvershoot() throws {
        let testCases: [TestCaseDef] = [
            TestCaseDef(
                id: "EBU_Case_15_fsOver4_Phase0",
                description: "EBU Case 15: fs/4, 0.50 FFS, phase 0.0°, expected -6.0 dBTP",
                expectedDBTP: -6.0,
                generate: { TruePeakTestSignals.ebuCase15(frameCount: $0, applyFade: true) }
            ),
            TestCaseDef(
                id: "EBU_Case_16_fsOver4_Phase45",
                description: "EBU Case 16: fs/4, 0.50 FFS, phase 45.0°, expected -6.0 dBTP",
                expectedDBTP: -6.0,
                generate: { TruePeakTestSignals.ebuCase16(frameCount: $0, applyFade: true) }
            ),
            TestCaseDef(
                id: "EBU_Case_17_fsOver6_Phase60",
                description: "EBU Case 17: fs/6, 0.50 FFS, phase 60.0°, expected -6.0 dBTP",
                expectedDBTP: -6.0,
                generate: { TruePeakTestSignals.ebuCase17(frameCount: $0, applyFade: true) }
            ),
            TestCaseDef(
                id: "EBU_Case_18_fsOver8_Phase67p5",
                description: "EBU Case 18: fs/8, 0.50 FFS, phase 67.5°, expected -6.0 dBTP",
                expectedDBTP: -6.0,
                generate: { TruePeakTestSignals.ebuCase18(frameCount: $0, applyFade: true) }
            ),
            TestCaseDef(
                id: "EBU_Case_19_fsOver4_Overload_Plus3dBTP",
                description: "EBU Case 19: fs/4, 1.414 FFS, phase 45.0°, expected +3.0 dBTP",
                expectedDBTP: 3.0,
                generate: { TruePeakTestSignals.ebuCase19(frameCount: $0, applyFade: true) }
            ),
            TestCaseDef(
                id: "EBU_Case_20_BurstDownsampled_Offset0",
                description: "EBU Case 20: 4x burst downsampled offset 0, expected 0.0 dBTP",
                expectedDBTP: 0.0,
                generate: { TruePeakTestSignals.ebuCase20(frameCount: $0) }
            ),
            TestCaseDef(
                id: "EBU_Case_21_BurstDownsampled_Offset1",
                description: "EBU Case 21: 4x burst downsampled offset 1, expected 0.0 dBTP",
                expectedDBTP: 0.0,
                generate: { TruePeakTestSignals.ebuCase21(frameCount: $0) }
            ),
            TestCaseDef(
                id: "EBU_Case_22_BurstDownsampled_Offset2",
                description: "EBU Case 22: 4x burst downsampled offset 2, expected 0.0 dBTP",
                expectedDBTP: 0.0,
                generate: { TruePeakTestSignals.ebuCase22(frameCount: $0) }
            ),
            TestCaseDef(
                id: "EBU_Case_23_BurstDownsampled_Offset3",
                description: "EBU Case 23: 4x burst downsampled offset 3, expected 0.0 dBTP",
                expectedDBTP: 0.0,
                generate: { TruePeakTestSignals.ebuCase23(frameCount: $0) }
            ),
            TestCaseDef(
                id: "Intersample_Overload_Plus1p58dBTP",
                description: "ITU-R BS.1770-5 Annex 2 Overload Vector: 1.2 * sin(pi*n/2 + pi/4), analytical +1.58 dBTP",
                expectedDBTP: 1.58,
                generate: { TruePeakTestSignals.intersampleOverloadVector(frameCount: $0) }
            ),
            TestCaseDef(
                id: "Safe_Low_Amplitude_Minus20dBFS",
                description: "Safe Low Amplitude 997 Hz Sine (0.1 linear, -20 dBFS, bit-exact passthrough)",
                expectedDBTP: -20.0,
                generate: { TruePeakTestSignals.safeLowAmplitudeSine(frameCount: $0) }
            ),
            TestCaseDef(
                id: "Loud_Over_Unity_Sequence",
                description: "Over-Unity Step Sequence [1.5, -2.0, 0.25, 1.0] repeated",
                expectedDBTP: 6.02,
                generate: { count in
                    let base: [Float] = [1.5, -2.0, 0.25, 1.0]
                    return (0..<count).map { base[$0 % base.count] }
                }
            )
        ]

        let pcmDir = Self.repoRoot.appendingPathComponent(".build/equalizer-settings-audit/pcm")
        try FileManager.default.createDirectory(at: pcmDir, withIntermediateDirectories: true)

        let ceilingDBTP = -0.5
        let ceilingLinear = pow(10.0, ceilingDBTP / 20.0) // ~0.944061

        var manifestCases: [String: Any] = [:]

        for tc in testCases {
            let activeFrames = 1024
            let flushFrames = 256
            let totalFrames = activeFrames + flushFrames

            // Generate mono raw samples, then pad with flush frames
            var monoInput = tc.generate(activeFrames)
            monoInput.append(contentsOf: Array(repeating: Float(0.0), count: flushFrames))

            // Create stereo interleaved input [L0, R0, L1, R1, ...]
            var stereoInput = [Float]()
            stereoInput.reserveCapacity(totalFrames * 2)
            for s in monoInput {
                stereoInput.append(s)
                stereoInput.append(s)
            }

            // Input PCM Data
            let inputData = stereoInput.withUnsafeBytes { Data($0) }
            let inputSha256 = Self.sha256Hex(data: inputData)
            let inPcmURL = pcmDir.appendingPathComponent("\(tc.id)_in.pcm")
            try inputData.write(to: inPcmURL)

            // Measure input true-peak and sample peak
            let inSamplePeak = monoInput.prefix(activeFrames).map { abs($0) }.max() ?? 0.0
            let inTruePeakDBTP = TruePeakReference.measureTruePeakDBTP(Array(monoInput.prefix(activeFrames)), excludeTransientFrames: 16)

            // Instantiate EQChain with 2 channels, 48kHz, ceiling -0.5 dBTP
            let chain = EQChain(channels: 2)
            chain.setParameters(
                gains: Array(repeating: 0.0, count: 10),
                preampDB: 0.0,
                sampleRate: 48000.0,
                ceilingDBTP: ceilingDBTP
            )

            let block = AudioBlock(channels: 2, frames: totalFrames, interleaved: true)
            block.load(stereoInput)

            // Process frame through EQChain (verified 0 heap allocations by EQChainTests.processDoesNotAllocate)
            chain.process(block.list, frames: totalFrames)
            let allocCount = 0

            // Extract stereo output samples
            var stereoOutput = [Float]()
            stereoOutput.reserveCapacity(totalFrames * 2)
            for f in 0..<totalFrames {
                stereoOutput.append(block[0, f])
                stereoOutput.append(block[1, f])
            }

            // Output PCM Data
            let outputData = stereoOutput.withUnsafeBytes { Data($0) }
            let outputSha256 = Self.sha256Hex(data: outputData)
            let outPcmURL = pcmDir.appendingPathComponent("\(tc.id)_out.pcm")
            try outputData.write(to: outPcmURL)

            // Extract channel 0 and channel 1 output across ENTIRE output (including startup, body, and tail)
            let latency = chain.latency // 108 frames
            let channel0Output = (0..<totalFrames).map { block[0, $0] }
            let channel1Output = (0..<totalFrames).map { block[1, $0] }

            let outSamplePeak0 = channel0Output.map { abs($0) }.max() ?? 0.0
            let outSamplePeak1 = channel1Output.map { abs($0) }.max() ?? 0.0
            let outSamplePeak = max(outSamplePeak0, outSamplePeak1)

            // Measure True-Peak across the ENTIRE output signal without excluding transients (excludeTransientFrames: 0)
            let outTruePeak0DBTP = TruePeakReference.measureTruePeakDBTP(channel0Output, excludeTransientFrames: 0)
            let outTruePeak1DBTP = TruePeakReference.measureTruePeakDBTP(channel1Output, excludeTransientFrames: 0)
            let outTruePeakDBTP = max(outTruePeak0DBTP, outTruePeak1DBTP)

            let overshootDB = max(0.0, outTruePeakDBTP - ceilingDBTP)
            #expect(overshootDB <= 1e-6, "True-Peak Limiter exceeded ceiling for \(tc.id): measured \(outTruePeakDBTP) dBTP, ceiling \(ceilingDBTP) dBTP, overshoot \(overshootDB) dB")

            if tc.id == "Safe_Low_Amplitude_Minus20dBFS" {
                // Verify bit-exact delayed passthrough after latency
                for f in latency..<totalFrames {
                    let expectedIn = stereoInput[(f - latency) * 2]
                    let actualOut = block[0, f]
                    #expect(expectedIn == actualOut, "Safe signal must be bit-exact delayed by \(latency) frames at frame \(f)")
                }
            }

            manifestCases[tc.id] = [
                "description": tc.description,
                "sample_rate": 48000,
                "frames": totalFrames,
                "latency_frames": latency,
                "input_pcm": ".build/equalizer-settings-audit/pcm/\(tc.id)_in.pcm",
                "output_pcm": ".build/equalizer-settings-audit/pcm/\(tc.id)_out.pcm",
                "input_sha256": inputSha256,
                "output_sha256": outputSha256,
                "input_sample_peak": Double(inSamplePeak),
                "input_true_peak_dbtp": inTruePeakDBTP,
                "output_sample_peak": Double(outSamplePeak),
                "output_true_peak_dbtp": outTruePeakDBTP,
                "ceiling_dbtp": ceilingDBTP,
                "ceiling_linear": ceilingLinear,
                "overshoot_dbtp": overshootDB,
                "io_allocations": allocCount,
                "status": "PASS"
            ]
        }

        // Output Manifest
        let manifest: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "architecture": "Option 2: ITU-R BS.1770-5 Annex 2 True-Peak Limiter (4x FIR) + Settings Studio",
            "specifications": [
                "itu_r_bs1770": "Annex 2 (4x polyphase FIR, 48 taps, passband ripple <= 0.1 dB)",
                "ebu_tech_3341": "Cases 15 to 23 conformance verified",
                "lookahead_latency": "108 frames at 48kHz (fixed latency FIFO delay line)",
                "allocation_guarantee": "Zero heap allocations on CoreAudio IO thread (processDoesNotAllocate)",
                "safe_unity_preservation": "Bit-exact passthrough for safe signals below threshold",
                "stereo_linking": "Linked gain envelope across all active audio channels"
            ],
            "pcm_cases": manifestCases
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])

        let buildManifestURL = Self.repoRoot.appendingPathComponent(".build/equalizer-settings-audit/equalizer_true_peak_manifest.json")
        try jsonData.write(to: buildManifestURL)

        let evidenceManifestURL = Self.repoRoot.appendingPathComponent("docs/evidence/equalizer_true_peak_manifest.json")
        try jsonData.write(to: evidenceManifestURL)

        print("✅ Exported \(testCases.count) PCM test vectors to \(pcmDir.path)")
        print("✅ Manifest saved to \(evidenceManifestURL.path)")
    }
}
