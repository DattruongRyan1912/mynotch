import EqualizerDSP
import MyNotchCore
import SwiftUI

/// Target frequency response curve preview across 20 Hz to 20 kHz.
/// Computes the theoretical combined magnitude response of the 10 peaking biquads plus preamp.
public struct EQResponseCurveView: View {
    public let profile: EQProfile
    public var sampleRate: Double

    public init(profile: EQProfile, sampleRate: Double = 48_000.0) {
        self.profile = profile
        self.sampleRate = sampleRate
    }

    private static let minFreq = 20.0
    private static let maxFreq = 20_000.0
    private static let logMin = log10(minFreq)
    private static let logMax = log10(maxFreq)
    private static let gridFrequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("MÔ PHỎNG ĐÁP TUYẾN MỤC TIÊU (TARGET CURVE PREVIEW)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("20 Hz — 20 kHz lý thuyết • Preamp: \(String(format: "%+.1f dB", profile.preamp))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2.0

                ZStack {
                    // Dark Zinc background with 1px hairline border
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )

                    // Grid lines: 0 dB line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: midY))
                        path.addLine(to: CGPoint(x: width, y: midY))
                    }
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)

                    // +12 dB and -12 dB dashed guidelines
                    Path { path in
                        let yPlus12 = midY - (12.0 / 24.0) * (height / 2.0 - 4)
                        let yMinus12 = midY - (-12.0 / 24.0) * (height / 2.0 - 4)
                        path.move(to: CGPoint(x: 0, y: yPlus12))
                        path.addLine(to: CGPoint(x: width, y: yPlus12))
                        path.move(to: CGPoint(x: 0, y: yMinus12))
                        path.addLine(to: CGPoint(x: width, y: yMinus12))
                    }
                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    // Vertical frequency grid lines for standard octave bands
                    ForEach(Self.gridFrequencies, id: \.self) { freq in
                        let x = xForFrequency(freq, width: width)
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: height))
                        }
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    }

                    // Response Curve Fill
                    responseAreaPath(width: width, height: height)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Response Curve Stroke
                    responseCurvePath(width: width, height: height)
                        .stroke(Color.accentColor, lineWidth: 1.5)

                    // Monospace dB labels on left/right edge
                    VStack {
                        HStack {
                            Text("+24")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Text("0")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Text("-24")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 90)

            // Frequency labels bar
            HStack {
                ForEach(Self.gridFrequencies, id: \.self) { freq in
                    Text(freqLabel(freq))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func xForFrequency(_ freq: Double, width: CGFloat) -> CGFloat {
        let clamped = min(max(freq, Self.minFreq), Self.maxFreq)
        let logVal = log10(clamped)
        let normalized = (logVal - Self.logMin) / (Self.logMax - Self.logMin)
        return CGFloat(normalized) * width
    }

    private func freqLabel(_ freq: Double) -> String {
        if freq >= 1000 {
            let k = Int(freq / 1000)
            return "\(k)k"
        } else {
            return "\(Int(freq))"
        }
    }

    private func calculateMagnitudes(stepCount: Int = 128) -> [(xFrac: Double, db: Double)] {
        let biquads = EQProfile.frequencies.indices.map { bandIndex -> BiquadCoefficients in
            let freq = EQProfile.frequencies[bandIndex]
            let gain = bandIndex < profile.gains.count ? profile.gains[bandIndex] : 0.0
            return BiquadCoefficients.peaking(frequency: freq, gainDB: gain, q: 1.414, sampleRate: sampleRate)
        }

        var results: [(xFrac: Double, db: Double)] = []
        results.reserveCapacity(stepCount)

        for i in 0..<stepCount {
            let frac = Double(i) / Double(stepCount - 1)
            let logFreq = Self.logMin + frac * (Self.logMax - Self.logMin)
            let freq = pow(10.0, logFreq)

            var magDB = profile.preamp
            for biquad in biquads {
                magDB += biquad.magnitudeDB(at: freq, sampleRate: sampleRate)
            }
            results.append((frac, magDB))
        }
        return results
    }

    private func responseCurvePath(width: CGFloat, height: CGFloat) -> Path {
        let points = calculateMagnitudes(stepCount: 160)
        let midY = height / 2.0
        let maxDB = 24.0
        let availableH = (height / 2.0) - 4.0

        var path = Path()
        guard let first = points.first else { return path }

        let firstY = midY - CGFloat(min(max(first.db, -maxDB), maxDB) / maxDB) * availableH
        path.move(to: CGPoint(x: 0, y: firstY))

        for point in points.dropFirst() {
            let x = CGFloat(point.xFrac) * width
            let clampedDB = min(max(point.db, -maxDB), maxDB)
            let y = midY - CGFloat(clampedDB / maxDB) * availableH
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }

    private func responseAreaPath(width: CGFloat, height: CGFloat) -> Path {
        var path = responseCurvePath(width: width, height: height)
        let midY = height / 2.0
        path.addLine(to: CGPoint(x: width, y: midY))
        path.addLine(to: CGPoint(x: 0, y: midY))
        path.closeSubpath()
        return path
    }
}
