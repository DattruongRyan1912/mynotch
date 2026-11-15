import CoreGraphics
import Foundation

/// Supported color representations for display and copy.
nonisolated enum ColorFormat: String, Codable, CaseIterable, Sendable {
    case hex
    case rgb
    case hsl
    case hsb

    var shortTitle: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .hsb: return "HSB"
        }
    }

    var title: String {
        switch self {
        case .hex: return "HEX (#RRGGBB)"
        case .rgb: return "RGB (r, g, b)"
        case .hsl: return "HSL (h, s%, l%)"
        case .hsb: return "HSB (h, s%, b%)"
        }
    }

    var next: ColorFormat {
        switch self {
        case .hex: return .rgb
        case .rgb: return .hsl
        case .hsl: return .hsb
        case .hsb: return .hex
        }
    }
}

/// An sRGB color sample with formatters and brightness metrics.
nonisolated struct ColorSample: Equatable, Sendable, Codable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Formats the color sample according to the requested format.
    func formatted(as format: ColorFormat) -> String {
        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", red, green, blue)

        case .rgb:
            return "rgb(\(red), \(green), \(blue))"

        case .hsl:
            let (h, s, l) = hslComponents()
            return "hsl(\(h), \(s)%, \(l)%)"

        case .hsb:
            let (h, s, b) = hsbComponents()
            return "hsb(\(h), \(s)%, \(b)%)"
        }
    }

    var cgColor: CGColor {
        CGColor(
            srgbRed: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: 1.0
        )
    }

    /// True if the color is bright enough that a dark crosshair/border provides better contrast.
    var prefersDarkCrosshair: Bool {
        let luminance = 0.2126 * (Double(red) / 255.0) +
                        0.7152 * (Double(green) / 255.0) +
                        0.0722 * (Double(blue) / 255.0)
        return luminance > 0.55
    }

    func hslComponents() -> (h: Int, s: Int, l: Int) {
        let r = Double(red) / 255.0
        let g = Double(green) / 255.0
        let b = Double(blue) / 255.0

        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal

        let l = (maxVal + minVal) / 2.0
        guard delta > 0.00001 else {
            return (0, 0, Int((l * 100.0).rounded()))
        }

        let s: Double = l > 0.5 ? delta / (2.0 - maxVal - minVal) : delta / (maxVal + minVal)

        var h: Double
        if maxVal == r {
            h = (g - b) / delta + (g < b ? 6.0 : 0.0)
        } else if maxVal == g {
            h = (b - r) / delta + 2.0
        } else {
            h = (r - g) / delta + 4.0
        }
        h *= 60.0

        let hInt = Int(h.rounded()) % 360
        let sInt = Int((s * 100.0).rounded())
        let lInt = Int((l * 100.0).rounded())
        return (hInt < 0 ? hInt + 360 : hInt, sInt, lInt)
    }

    func hsbComponents() -> (h: Int, s: Int, b: Int) {
        let r = Double(red) / 255.0
        let g = Double(green) / 255.0
        let bVal = Double(blue) / 255.0

        let maxVal = max(r, g, bVal)
        let minVal = min(r, g, bVal)
        let delta = maxVal - minVal

        let brightness = maxVal
        guard maxVal > 0.00001 && delta > 0.00001 else {
            return (0, 0, Int((brightness * 100.0).rounded()))
        }

        let s = delta / maxVal

        var h: Double
        if maxVal == r {
            h = (g - bVal) / delta + (g < bVal ? 6.0 : 0.0)
        } else if maxVal == g {
            h = (bVal - r) / delta + 2.0
        } else {
            h = (r - g) / delta + 4.0
        }
        h *= 60.0

        let hInt = Int(h.rounded()) % 360
        let sInt = Int((s * 100.0).rounded())
        let bInt = Int((brightness * 100.0).rounded())
        return (hInt < 0 ? hInt + 360 : hInt, sInt, bInt)
    }
}

/// Extracts pixel sRGB colors and grids directly from a frozen display CGImage.
nonisolated struct FrozenDisplaySampler: Sendable {
    let width: Int
    let height: Int
    private let pixelBytes: [UInt8]

    init?(image: CGImage) {
        let imgWidth = image.width
        let imgHeight = image.height
        guard imgWidth > 0 && imgHeight > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = imgWidth * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: imgHeight * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let rendered = buffer.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            guard let context = CGContext(
                data: base,
                width: imgWidth,
                height: imgHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))
            return true
        }

        guard rendered else { return nil }
        self.width = imgWidth
        self.height = imgHeight
        self.pixelBytes = buffer
    }

    /// Samples color at image pixel coordinates (origin at top-left, y down).
    func sample(atX x: Int, y: Int) -> ColorSample {
        guard width > 0 && height > 0 else {
            return ColorSample(red: 0, green: 0, blue: 0)
        }
        let clampedX = min(max(x, 0), width - 1)
        let clampedY = min(max(y, 0), height - 1)
        let offset = (clampedY * width + clampedX) * 4

        guard offset + 2 < pixelBytes.count else {
            return ColorSample(red: 0, green: 0, blue: 0)
        }

        let r = pixelBytes[offset]
        let g = pixelBytes[offset + 1]
        let b = pixelBytes[offset + 2]
        return ColorSample(red: r, green: g, blue: b)
    }

    /// Returns a (2 * radius + 1) × (2 * radius + 1) matrix of samples centered at (centerX, centerY).
    func grid(centerX: Int, centerY: Int, radius: Int = 5) -> [[ColorSample]] {
        var result: [[ColorSample]] = []
        for y in (centerY - radius)...(centerY + radius) {
            var row: [ColorSample] = []
            for x in (centerX - radius)...(centerX + radius) {
                row.append(sample(atX: x, y: y))
            }
            result.append(row)
        }
        return result
    }
}
