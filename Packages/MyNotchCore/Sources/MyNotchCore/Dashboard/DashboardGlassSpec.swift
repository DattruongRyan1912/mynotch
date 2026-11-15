import Foundation

/// Pure RGBA representation and color math for Liquid Glass design specification.
/// Contains no SwiftUI or AppKit dependencies to run portably in all test suites.
public struct GlassRGBA: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = min(max(r, 0.0), 255.0)
        self.g = min(max(g, 0.0), 255.0)
        self.b = min(max(b, 0.0), 255.0)
        self.a = min(max(a, 0.0), 1.0)
    }

    public static let white = GlassRGBA(r: 255, g: 255, b: 255, a: 1.0)
    public static let black = GlassRGBA(r: 0, g: 0, b: 0, a: 1.0)
    public static let clear = GlassRGBA(r: 0, g: 0, b: 0, a: 0.0)

    public static let screenshotDark = GlassRGBA(r: 30, g: 32, b: 41, a: 1.0)
    public static let midGray = GlassRGBA(r: 127, g: 127, b: 127, a: 1.0)

    // Palette Tokens
    public static let slate900 = GlassRGBA(r: 15, g: 23, b: 42, a: 1.0)
    public static let slate700 = GlassRGBA(r: 51, g: 65, b: 85, a: 1.0)
    public static let slate600 = GlassRGBA(r: 71, g: 85, b: 105, a: 1.0)
    public static let slate500 = GlassRGBA(r: 100, g: 116, b: 139, a: 1.0)
}

public enum DashboardGlassSpec {
    // MARK: - Layer Tokens

    public static let rootWash = GlassRGBA(r: 255, g: 255, b: 255, a: 0.86)
    public static let sidebarFill = GlassRGBA(r: 255, g: 255, b: 255, a: 0.60)
    public static let headerFill = GlassRGBA(r: 255, g: 255, b: 255, a: 0.55)
    public static let card = GlassRGBA(r: 255, g: 255, b: 255, a: 0.88)
    public static let cardHover = GlassRGBA(r: 255, g: 255, b: 255, a: 0.96)
    public static let row = GlassRGBA(r: 255, g: 255, b: 255, a: 0.70)
    public static let inset = GlassRGBA(r: 15, g: 23, b: 42, a: 0.045)
    public static let insetBorder = GlassRGBA(r: 100, g: 116, b: 139, a: 0.28)
    public static let control = GlassRGBA(r: 255, g: 255, b: 255, a: 0.90)
    public static let controlBorder = GlassRGBA(r: 100, g: 116, b: 139, a: 0.30)
    public static let segmentTrack = GlassRGBA(r: 15, g: 23, b: 42, a: 0.08)
    public static let chip = GlassRGBA(r: 100, g: 116, b: 139, a: 0.16)
    public static let separator = GlassRGBA(r: 15, g: 23, b: 42, a: 0.10)
    public static let navActive = GlassRGBA(r: 255, g: 255, b: 255, a: 1.0)

    public static let specularBorder = GlassRGBA(r: 255, g: 255, b: 255, a: 0.95)
    public static let outerEdgeBorder = GlassRGBA(r: 15, g: 23, b: 42, a: 0.10)

    // MARK: - Typography & Semantic Ink Tokens

    public static let textPrimary = GlassRGBA(r: 15, g: 23, b: 42, a: 1.0)       // #0f172a
    public static let textSecondary = GlassRGBA(r: 51, g: 65, b: 85, a: 1.0)     // #334155
    public static let textMuted = GlassRGBA(r: 71, g: 85, b: 105, a: 1.0)       // #475569 (Slate 600, ensures >= 4.5:1 AA)

    public static let accentText = GlassRGBA(r: 29, g: 78, b: 216, a: 1.0)      // #1d4ed8 (Blue 700)
    public static let successText = GlassRGBA(r: 6, g: 95, b: 70, a: 1.0)        // #065f46 (Emerald 800, ensures >= 4.5:1 AA)
    public static let warningText = GlassRGBA(r: 146, g: 64, b: 14, a: 1.0)      // #92400e (Amber 800)
    public static let dangerText = GlassRGBA(r: 185, g: 28, b: 28, a: 1.0)       // #b91c1c (Red 700)

    // MARK: - Surfaces

    public enum Surface: CaseIterable, Sendable {
        case root
        case sidebar
        case header
        case card
        case row
        case inset
        case control
        case chip

        public var layers: [GlassRGBA] {
            switch self {
            case .root:
                return [DashboardGlassSpec.rootWash]
            case .sidebar:
                return [DashboardGlassSpec.rootWash, DashboardGlassSpec.sidebarFill]
            case .header:
                return [DashboardGlassSpec.rootWash, DashboardGlassSpec.headerFill]
            case .card:
                return [DashboardGlassSpec.rootWash, DashboardGlassSpec.card]
            case .row:
                return [DashboardGlassSpec.rootWash, DashboardGlassSpec.card, DashboardGlassSpec.row]
            case .inset:
                return [DashboardGlassSpec.rootWash, DashboardGlassSpec.card, DashboardGlassSpec.inset]
            case .control:
                return [DashboardGlassSpec.rootWash, DashboardGlassSpec.headerFill, DashboardGlassSpec.control]
            case .chip:
                return [DashboardGlassSpec.rootWash, DashboardGlassSpec.card, DashboardGlassSpec.chip]
            }
        }
    }

    // MARK: - Composite & Color Math

    /// Source-over compositing of layers over an opaque or translucent backdrop.
    public static func composite(_ layers: [GlassRGBA], over backdrop: GlassRGBA) -> GlassRGBA {
        var current = backdrop
        for layer in layers {
            let a = min(max(layer.a, 0.0), 1.0)
            guard a > 0 else { continue }
            if a >= 1.0 {
                current = layer
                continue
            }
            let r = layer.r * a + current.r * (1.0 - a)
            let g = layer.g * a + current.g * (1.0 - a)
            let b = layer.b * a + current.b * (1.0 - a)
            let outA = a + current.a * (1.0 - a)
            current = GlassRGBA(r: r, g: g, b: b, a: outA)
        }
        return current
    }

    public static func sRGBToLinear(_ c255: Double) -> Double {
        let v = min(max(c255, 0.0), 255.0) / 255.0
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    public static func relativeLuminance(_ color: GlassRGBA) -> Double {
        let r = sRGBToLinear(color.r)
        let g = sRGBToLinear(color.g)
        let b = sRGBToLinear(color.b)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    public static func luma255(_ color: GlassRGBA) -> Double {
        return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
    }

    public static func wcagContrast(_ c1: GlassRGBA, _ c2: GlassRGBA) -> Double {
        let l1 = relativeLuminance(c1)
        let l2 = relativeLuminance(c2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
