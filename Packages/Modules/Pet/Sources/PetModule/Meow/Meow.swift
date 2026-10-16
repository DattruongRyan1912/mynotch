import AppKit
import Foundation

/// The sound of a click on the cat, if the user wants one.
protocol MeowPlayer {
    func play()
}

/// A meow made of numbers, so the module needs no sound file: a note that glides up and down, with the harmonics a throat has at the
/// pitch it has, which is what a mew is.
nonisolated enum MeowSynth {
    static let sampleRate = 22_050
    static let duration = 0.5

    /// The samples, signed 16-bit, mono.
    static func samples() -> [Int16] {
        let count = Int(Double(sampleRate) * duration)
        var phase = 0.0
        var result = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            let progress = time / duration
            // Up to a peak a third of the way through, then down to a little under where it began: "mrr-ow".
            let glide = progress < 0.35 ? progress / 0.35 : 1 - (progress - 0.35) / 0.65 * 0.75
            let pitch = 430 + 330 * sin(glide * .pi / 2) + 8 * sin(2 * .pi * 6 * time)
            phase += 2 * .pi * pitch / Double(sampleRate)
            var value = 0.0
            for harmonic in 1...10 {
                let frequency = pitch * Double(harmonic)
                guard frequency < Double(sampleRate) / 2 else { break }
                // Strongest near 1.2 kHz, where a cat's throat rings.
                let formant = exp(-pow((frequency - 1200) / 900, 2)) + 0.12
                value += formant / Double(harmonic) * sin(phase * Double(harmonic))
            }
            let attack = min(time / 0.04, 1)
            let release = min((duration - time) / 0.18, 1)
            result[index] = Int16((value * 0.28 * attack * release * Double(Int16.max)).rounded())
        }
        return result
    }

    /// The same as a WAV file's bytes: what a sound can be made from without a file.
    static func wav() -> Data {
        let samples = samples()
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(bytes)
        samples.forEach { append($0) }
        return data
    }
}

/// Plays `MeowSynth`'s meow, made the first time it is wanted.
final class SynthMeow: MeowPlayer {
    private var sound: NSSound?

    func play() {
        if sound == nil { sound = NSSound(data: MeowSynth.wav()) }
        sound?.stop()
        sound?.play()
    }
}
