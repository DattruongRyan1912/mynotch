import AudioToolbox
import AVFoundation
import Foundation
import EqualizerDSP

/// Provides pristine 64-bit biquad coefficients by querying Apple's native CoreAudio `AUNBandEQ` unit
/// (`kAUNBandEQProperty_BiquadCoefficients`, Property ID 2203) with parametric filters and 0.5 octave bandwidth,
/// exactly matching eqMac's acoustic response while keeping MyNotch's driverless zero-allocation real-time tap.
///
/// This provider operates strictly on the main actor / control thread, never on the real-time IO thread.
@MainActor
public final class AppleEQCoefficientProvider: @unchecked Sendable {
    private var audioUnit: AudioComponentInstance?
    private var currentSampleRate: Double = 0
    private let bandCount: Int

    public init() {
        self.bandCount = EQChain.frequencies.count
        setupAudioUnit()
    }

    isolated deinit {
        if let au = audioUnit {
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
        }
    }

    private func setupAudioUnit() {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_NBandEQ,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else { return }
        var au: AudioComponentInstance?
        let status = AudioComponentInstanceNew(comp, &au)
        guard status == noErr, let instance = au else { return }
        self.audioUnit = instance

        // Configure number of bands
        var numBands = UInt32(bandCount)
        AudioUnitSetProperty(
            instance,
            kAUNBandEQProperty_NumberOfBands,
            kAudioUnitScope_Global,
            0,
            &numBands,
            UInt32(MemoryLayout<UInt32>.size)
        )

        // Configure parametric filter type and 0.5 octave bandwidth (matching eqMac)
        for i in 0..<bandCount {
            let bandIndex = UInt32(i)
            // FilterType: 0 = Parametric
            AudioUnitSetParameter(
                instance,
                kAUNBandEQParam_FilterType + bandIndex,
                kAudioUnitScope_Global,
                0,
                0.0,
                0
            )
            // Bandwidth: 0.5 octave
            AudioUnitSetParameter(
                instance,
                kAUNBandEQParam_Bandwidth + bandIndex,
                kAudioUnitScope_Global,
                0,
                0.5,
                0
            )
        }
    }

    private func ensureSampleRate(_ sampleRate: Double) -> Bool {
        guard let au = audioUnit else { return false }
        if abs(currentSampleRate - sampleRate) < 1.0 { return true }

        AudioUnitUninitialize(au)

        var streamDesc = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        let inStatus = AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &streamDesc,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        let outStatus = AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            0,
            &streamDesc,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        let initStatus = AudioUnitInitialize(au)
        guard inStatus == noErr, outStatus == noErr, initStatus == noErr else {
            return false
        }
        currentSampleRate = sampleRate
        return true
    }

    /// Computes 64-bit biquad coefficients for the given 10 band gains at `sampleRate`.
    /// Falls back to RBJ peaking filters if AudioUnit is unavailable.
    public func coefficients(gains: [Double], sampleRate: Double) -> [BiquadCoefficients] {
        guard sampleRate.isFinite, sampleRate > 0 else {
            return Array(repeating: .identity, count: bandCount)
        }

        let frequencies = EQChain.frequencies
        let safeGains = (0..<bandCount).map { i -> Double in
            guard i < gains.count, gains[i].isFinite else { return 0.0 }
            return min(max(gains[i], EQChain.gainRange.lowerBound), EQChain.gainRange.upperBound)
        }

        // Quick check: if all valid bands are 0 dB, return identity
        let allZero = safeGains.indices.allSatisfy { i in
            let f = frequencies[i]
            if f >= sampleRate * BiquadCoefficients.highestCentre { return true }
            return abs(safeGains[i]) < 1e-9
        }
        if allZero {
            return Array(repeating: .identity, count: bandCount)
        }

        guard let au = audioUnit, ensureSampleRate(sampleRate) else {
            // Fallback to RBJ Peaking
            return frequencies.indices.map { i in
                BiquadCoefficients.peaking(
                    frequency: frequencies[i],
                    gainDB: safeGains[i],
                    q: EQChain.q,
                    sampleRate: sampleRate
                )
            }
        }

        // Set parameters for each band
        for i in 0..<bandCount {
            let bandIndex = UInt32(i)
            let f = frequencies[i]
            let gain = safeGains[i]

            if f >= sampleRate * BiquadCoefficients.highestCentre || abs(gain) < 1e-9 {
                // Bypass this band or zero gain
                AudioUnitSetParameter(au, kAUNBandEQParam_BypassBand + bandIndex, kAudioUnitScope_Global, 0, 1.0, 0)
                AudioUnitSetParameter(au, kAUNBandEQParam_Gain + bandIndex, kAudioUnitScope_Global, 0, 0.0, 0)
                // Use safe frequency
                let safeFreq = min(f, sampleRate * 0.4)
                AudioUnitSetParameter(au, kAUNBandEQParam_Frequency + bandIndex, kAudioUnitScope_Global, 0, Float(safeFreq), 0)
            } else {
                AudioUnitSetParameter(au, kAUNBandEQParam_BypassBand + bandIndex, kAudioUnitScope_Global, 0, 0.0, 0)
                AudioUnitSetParameter(au, kAUNBandEQParam_Frequency + bandIndex, kAudioUnitScope_Global, 0, Float(f), 0)
                AudioUnitSetParameter(au, kAUNBandEQParam_Gain + bandIndex, kAudioUnitScope_Global, 0, Float(gain), 0)
            }
        }

        // Read property 2203: kAUNBandEQProperty_BiquadCoefficients
        var propSize = UInt32(bandCount * 5 * MemoryLayout<Float64>.size)
        var rawCoeffs = [Float64](repeating: 0, count: bandCount * 5)
        let getStatus = AudioUnitGetProperty(
            au,
            2203,
            kAudioUnitScope_Global,
            0,
            &rawCoeffs,
            &propSize
        )

        guard getStatus == noErr, propSize == UInt32(bandCount * 5 * MemoryLayout<Float64>.size) else {
            // Fallback to RBJ Peaking
            return frequencies.indices.map { i in
                BiquadCoefficients.peaking(
                    frequency: frequencies[i],
                    gainDB: safeGains[i],
                    q: EQChain.q,
                    sampleRate: sampleRate
                )
            }
        }

        var result = [BiquadCoefficients]()
        result.reserveCapacity(bandCount)
        for i in 0..<bandCount {
            let f = frequencies[i]
            let gain = safeGains[i]
            if f >= sampleRate * BiquadCoefficients.highestCentre || abs(gain) < 1e-9 {
                result.append(.identity)
            } else {
                let base = i * 5
                let bandRaw = Array(rawCoeffs[base..<(base + 5)])
                let coeff = BiquadCoefficients.fromAppleAUNBandEQ(raw: bandRaw)
                result.append(coeff)
            }
        }
        return result
    }
}
