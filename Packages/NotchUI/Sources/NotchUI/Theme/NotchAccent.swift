import AppKit
import SwiftUI

/// The colour the notch marks its controls with: the selected tab, progress, toggles. The notch itself stays black.
nonisolated public enum NotchAccent: Equatable, Sendable {
    /// Whatever macOS's accent is, also after the user changes it.
    case system
    case palette(Palette)
    case custom(RGB)

    /// The eight colours of macOS's own accent picker, in its order, as macOS shows them on a dark surface.
    public enum Palette: String, CaseIterable, Sendable {
        case blue, purple, pink, red, orange, yellow, green, graphite

        public var rgb: RGB {
            switch self {
            case .blue: RGB(red: 10, green: 132, blue: 255)
            case .purple: RGB(red: 191, green: 90, blue: 242)
            case .pink: RGB(red: 255, green: 55, blue: 95)
            case .red: RGB(red: 255, green: 69, blue: 58)
            case .orange: RGB(red: 255, green: 159, blue: 10)
            case .yellow: RGB(red: 255, green: 214, blue: 10)
            case .green: RGB(red: 48, green: 209, blue: 88)
            case .graphite: RGB(red: 152, green: 152, blue: 157)
            }
        }
    }

    /// An sRGB colour in 8 bits a channel, which is also how a custom one is stored.
    public struct RGB: Hashable, Sendable {
        public var red: UInt8
        public var green: UInt8
        public var blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            (self.red, self.green, self.blue) = (red, green, blue)
        }

        /// How much the selection capsule has to stand out from the black notch, as a contrast ratio against black. The white
        /// at 0.14 that the selected tab used to be is 1.35:1, so no accent marks a selection fainter than that did.
        static let minimumSelectionContrast = 1.35

        /// The contrast against black (WCAG's ratio) of this colour drawn as the selected tab's capsule, which is the accent at
        /// `NotchTokens.selectionOpacity` over black.
        var selectionContrast: Double {
            func linear(_ channel: UInt8) -> Double {
                let value = Double(channel) / 255 * Double(NotchTokens.selectionOpacity)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
            return (luminance + 0.05) / 0.05
        }

        /// Itself, or the colour mixed with as little white as it takes for the selection capsule to show on black: a custom
        /// pick of (nearly) black, or a deep blue, would otherwise mark nothing. A dark colour stays the same kind of colour
        /// (black has no hue and becomes grey), and one that already shows, which is every palette colour, is not changed.
        var legibleOnBlack: RGB {
            guard selectionContrast < Self.minimumSelectionContrast else { return self }
            func mixed(_ channel: UInt8, _ white: Double) -> UInt8 { UInt8((Double(channel) + (255 - Double(channel)) * white).rounded()) }
            for step in 1...255 {
                let white = Double(step) / 255
                let candidate = RGB(red: mixed(red, white), green: mixed(green, white), blue: mixed(blue, white))
                if candidate.selectionContrast >= Self.minimumSelectionContrast { return candidate }
            }
            return RGB(red: 255, green: 255, blue: 255)
        }

        var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

        init?(hex: String) {
            let digits = hex.dropFirst()
            guard hex.first == "#", digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
            self.init(red: UInt8(value >> 16), green: UInt8((value >> 8) & 0xFF), blue: UInt8(value & 0xFF))
        }

        public var color: Color {
            Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
        }

        /// For AppKit drawing.
        public var nsColor: NSColor {
            NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        }

        /// For a layer's `backgroundColor`, `borderColor` or `shadowColor` and for Core Graphics drawing; a layer keeps the
        /// colour it was given, so it has to be set again when the accent changes (see `NotchInterface.accentRGB`).
        public var cgColor: CGColor { nsColor.cgColor }
    }

    /// The colour to draw with: the choice, or `system` (what macOS's accent is at that moment, only read when the choice
    /// is `system`), lifted if the selection capsule would not show on a black notch (see `RGB.legibleOnBlack`).
    public func resolved(system: @autoclosure () -> RGB) -> RGB {
        switch self {
        case .system: system().legibleOnBlack
        case .palette(let palette): palette.rgb.legibleOnBlack
        case .custom(let rgb): rgb.legibleOnBlack
        }
    }

    /// A colour from a colour picker, as a custom accent.
    public init(color: Color) {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        func byte(_ component: CGFloat) -> UInt8 { UInt8((min(max(component, 0), 1) * 255).rounded()) }
        self = .custom(RGB(red: byte(srgb.redComponent), green: byte(srgb.greenComponent), blue: byte(srgb.blueComponent)))
    }

    /// The colour for a page that shows the choice (a swatch), with the system accent as it is now.
    public var color: Color { resolved(system: SystemAccent.current()).color }
}

/// Stored as one short string: `system`, `palette:<name>` or `custom:#RRGGBB`. Anything else cannot be read, so the
/// setting falls back to its default.
nonisolated extension NotchAccent: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let accent = NotchAccent(stored: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an accent")
        }
        self = accent
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stored)
    }

    private var stored: String {
        switch self {
        case .system: "system"
        case .palette(let palette): "palette:\(palette.rawValue)"
        case .custom(let rgb): "custom:\(rgb.hex)"
        }
    }

    private init?(stored: String) {
        if stored == "system" {
            self = .system
        } else if stored.hasPrefix("palette:"), let palette = Palette(rawValue: String(stored.dropFirst("palette:".count))) {
            self = .palette(palette)
        } else if stored.hasPrefix("custom:"), let rgb = RGB(hex: String(stored.dropFirst("custom:".count))) {
            self = .custom(rgb)
        } else {
            return nil
        }
    }
}

/// The accent macOS shows now.
nonisolated public enum SystemAccent {
    /// `accent` (macOS's accent unless a test says otherwise) as it looks on a dark surface, whatever the app's appearance
    /// is: the notch is black in both.
    public static func current(of accent: NSColor = .controlAccentColor) -> NotchAccent.RGB {
        var result = NotchAccent.Palette.blue.rgb
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            guard let color = accent.usingColorSpace(.sRGB) else { return }
            func byte(_ component: CGFloat) -> UInt8 { UInt8((min(max(component, 0), 1) * 255).rounded()) }
            result = NotchAccent.RGB(red: byte(color.redComponent), green: byte(color.greenComponent), blue: byte(color.blueComponent))
        }
        return result
    }
}
