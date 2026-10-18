import Foundation

/// A colour as lightness, chroma and hue in OKLab, a space whose steps look even: a colour made lighter there with its hue kept
/// still looks like the same colour, which the channels of sRGB do not give. Plain numbers, so it runs off the main actor.
nonisolated struct OKLCH: Equatable, Sendable {
    /// 0 (black) to 1 (white).
    var lightness: Double
    /// 0 for greys; about 0.3 is the most any sRGB colour has.
    var chroma: Double
    /// Degrees, 0..<360.
    var hue: Double

    init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    init(_ color: SRGBColor) {
        let (r, g, b) = (Self.linear(color.red), Self.linear(color.green), Self.linear(color.blue))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bAxis = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        chroma = (a * a + bAxis * bAxis).squareRoot()
        let degrees = atan2(bAxis, a) * 180 / .pi
        hue = degrees < 0 ? degrees + 360 : degrees
    }

    /// The colour in linear sRGB, not kept inside 0...1: a channel outside it says the colour is not one sRGB can show.
    private var linearRGB: (red: Double, green: Double, blue: Double) {
        let radians = hue * .pi / 180
        let (a, b) = (chroma * cos(radians), chroma * sin(radians))
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    /// Whether sRGB can show the colour.
    var fitsInSRGB: Bool {
        let (r, g, b) = linearRGB
        let slack = 1e-7
        return [r, g, b].allSatisfy { $0 >= -slack && $0 <= 1 + slack }
    }

    /// The colour in sRGB. One that does not fit loses chroma, at the same lightness and hue, until it does; clipping its channels
    /// instead would move its hue and its lightness.
    var srgb: SRGBColor {
        let fitted = fitsInSRGB ? self : OKLCH(
            lightness: lightness, chroma: Self.maxChroma(lightness: lightness, hue: hue), hue: hue
        )
        let (r, g, b) = fitted.linearRGB
        return SRGBColor(red: Self.encode(r), green: Self.encode(g), blue: Self.encode(b))
    }

    /// The most chroma sRGB can show at `lightness` and `hue`, found by bisection: the shape of the gamut is not a formula.
    static func maxChroma(lightness: Double, hue: Double) -> Double {
        guard lightness > 0, lightness < 1 else { return 0 }
        var (low, high) = (0.0, 0.4)
        for _ in 0..<28 {
            let middle = (low + high) / 2
            if OKLCH(lightness: lightness, chroma: middle, hue: hue).fitsInSRGB { low = middle } else { high = middle }
        }
        return low
    }

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func encode(_ linear: Double) -> Double {
        let value = min(max(linear, 0), 1)
        return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

extension SRGBColor {
    /// The colour made lighter, and no lighter than it takes to reach `minimum` luminance, with its hue kept. A colour that is light
    /// enough is returned as it is, and one is never made darker. The lightness grows in OKLCH, and the colour keeps the same share
    /// of the chroma sRGB can show at each lightness, so a deep red becomes a clear red rather than a pale one; a grey stays grey.
    func liftedKeepingHue(toLuminance minimum: Double) -> SRGBColor {
        guard luminance < minimum, minimum <= 1 else { return self }
        let origin = OKLCH(self)
        let room = OKLCH.maxChroma(lightness: origin.lightness, hue: origin.hue)
        let share = room > 1e-6 ? min(origin.chroma / room, 1) : 0
        func at(_ lightness: Double) -> SRGBColor {
            OKLCH(lightness: lightness, chroma: share * OKLCH.maxChroma(lightness: lightness, hue: origin.hue), hue: origin.hue).srgb
        }
        // Luminance only grows with lightness here, and white is light enough, so a bisection finds the smallest lightness that is.
        var (low, high) = (origin.lightness, 1.0)
        for _ in 0..<40 {
            let middle = (low + high) / 2
            if at(middle).luminance >= minimum { high = middle } else { low = middle }
        }
        return at(high)
    }
}
