import Foundation

/// A colour in sRGB, each channel 0...1. Plain numbers, so it can be computed off the main actor, stored in the settings and
/// compared, which SwiftUI's `Color` and `NSColor` cannot do reliably.
nonisolated struct SRGBColor: Hashable, Codable, Sendable {
    /// The least relative luminance a colour drawn on the notch's black may have: a contrast of 3 to 1 against black, which is
    /// what the WCAG asks of graphics (a progress bar, a row of bars).
    static let minimumLuminance = 0.10

    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.unit(red)
        self.green = Self.unit(green)
        self.blue = Self.unit(blue)
    }

    /// A colour as it is written in hex, `0xRRGGBB`.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255
        )
    }

    private enum CodingKeys: String, CodingKey { case red, green, blue }

    /// A stored value is read back kept inside 0...1, so a hand-edited setting cannot make a colour that does not exist.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue)
        )
    }

    private static func unit(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }

    /// Relative luminance as the WCAG defines it: 0 for black, 1 for white.
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The contrast ratio against black, 1 (invisible) to 21 (white).
    var contrastOnBlack: Double { contrast(with: .init(red: 0, green: 0, blue: 0)) }

    /// The contrast ratio against `other` as the WCAG defines it, 1 (the same) to 21 (black on white), whichever is lighter.
    func contrast(with other: SRGBColor) -> Double {
        let (lighter, darker) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// 0 for greys, 1 for a colour with no grey in it.
    var saturation: Double {
        let peak = max(red, green, blue)
        return peak > 0 ? (peak - min(red, green, blue)) / peak : 0
    }

    /// Straight-line distance between the two colours' channels, 0...√3.
    func distance(to other: SRGBColor) -> Double {
        squaredDistance(to: other).squareRoot()
    }

    func squaredDistance(to other: SRGBColor) -> Double {
        let (dr, dg, db) = (red - other.red, green - other.green, blue - other.blue)
        return dr * dr + dg * dg + db * db
    }

    /// `amount` of the way to `other`, kept inside 0...1. Exactly `self` at 0 and exactly `other` at 1.
    func mixed(with other: SRGBColor, amount: Double) -> SRGBColor {
        let t = Self.unit(amount)
        return SRGBColor(
            red: red * (1 - t) + other.red * t, green: green * (1 - t) + other.green * t, blue: blue * (1 - t) + other.blue * t
        )
    }

    /// The nearest colour with at least `minimum` luminance. A bright enough colour is returned as it is. A darker one first gets
    /// brighter with its hue and saturation kept, as far as it can; if that is not enough (a deep blue cannot be bright
    /// enough on its own) it is mixed with white, by as little as will do. Black becomes the darkest grey that qualifies.
    func lifted(toLuminance minimum: Double) -> SRGBColor {
        guard luminance < minimum else { return self }
        var base = self
        let peak = max(red, green, blue)
        if peak > 0 {
            let brightest = scaled(by: 1 / peak)
            if brightest.luminance >= minimum {
                return Self.smallest(from: 1, to: 1 / peak, reaching: minimum) { scaled(by: $0) }
            }
            base = brightest
        }
        return Self.smallest(from: 0, to: 1, reaching: minimum) { base.mixed(with: SRGBColor(red: 1, green: 1, blue: 1), amount: $0) }
    }

    private func scaled(by factor: Double) -> SRGBColor {
        SRGBColor(red: red * factor, green: green * factor, blue: blue * factor)
    }

    /// Luminance only grows with the parameter, so a bisection finds the smallest value in `low...high` that reaches `minimum`.
    private static func smallest(from low: Double, to high: Double, reaching minimum: Double, make: (Double) -> SRGBColor) -> SRGBColor {
        var (low, high) = (low, high)
        for _ in 0..<32 {
            let middle = (low + high) / 2
            if make(middle).luminance >= minimum { high = middle } else { low = middle }
        }
        return make(high)
    }
}
