import CoreGraphics
import Foundation

/// Backdrop presets for Studio Frame mockup.
nonisolated enum StudioBackdrop: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case tahoe
    case sunset
    case ocean
    case midnight
    case graphite
    case zincDark
    case snowWhite
    case transparent

    var title: String {
        switch self {
        case .none: "Tắt"
        case .tahoe: "Tahoe"
        case .sunset: "Hoàng hôn"
        case .ocean: "Đại dương"
        case .midnight: "Nửa đêm"
        case .graphite: "Than chì"
        case .zincDark: "Zinc 950"
        case .snowWhite: "Trắng sáng"
        case .transparent: "Trong suốt"
        }
    }

    var gradientColors: (start: RGBAColor, end: RGBAColor)? {
        switch self {
        case .tahoe:
            return (
                start: RGBAColor(r: 0.12, g: 0.45, b: 0.68),
                end: RGBAColor(r: 0.18, g: 0.72, b: 0.82)
            )
        case .sunset:
            return (
                start: RGBAColor(r: 0.85, g: 0.25, b: 0.45),
                end: RGBAColor(r: 0.95, g: 0.65, b: 0.25)
            )
        case .ocean:
            return (
                start: RGBAColor(r: 0.08, g: 0.18, b: 0.38),
                end: RGBAColor(r: 0.15, g: 0.42, b: 0.75)
            )
        case .midnight:
            return (
                start: RGBAColor(r: 0.12, g: 0.08, b: 0.25),
                end: RGBAColor(r: 0.25, g: 0.15, b: 0.45)
            )
        case .graphite:
            return (
                start: RGBAColor(r: 0.18, g: 0.18, b: 0.20),
                end: RGBAColor(r: 0.08, g: 0.08, b: 0.10)
            )
        case .none, .zincDark, .snowWhite, .transparent:
            return nil
        }
    }

    var solidColor: RGBAColor? {
        switch self {
        case .zincDark:
            return RGBAColor(r: 9.0 / 255.0, g: 9.0 / 255.0, b: 11.0 / 255.0)
        case .snowWhite:
            return RGBAColor(r: 244.0 / 255.0, g: 244.0 / 255.0, b: 245.0 / 255.0)
        default:
            return nil
        }
    }
}

/// Configuration settings for rendering Studio Frame mockup around a capture.
nonisolated struct StudioFrameConfig: Codable, Equatable, Sendable {
    var backdrop: StudioBackdrop = .none
    var padding: Int = 48
    var cornerRadius: Int = 12
    var shadowRadius: Int = 24

    var isActive: Bool { backdrop != .none }

    static let paddingPresets = [0, 24, 48, 72]
    static let cornerRadiusPresets = [0, 12, 20]
    static let shadowRadiusPresets = [0, 16, 32]

    static let defaultActive = StudioFrameConfig(
        backdrop: .tahoe,
        padding: 48,
        cornerRadius: 12,
        shadowRadius: 24
    )

    init(
        backdrop: StudioBackdrop = .none,
        padding: Int = 48,
        cornerRadius: Int = 12,
        shadowRadius: Int = 24
    ) {
        self.backdrop = backdrop
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
    }
}

/// Renders a capture composited inside a backdrop with rounded corners and drop shadow.
nonisolated enum StudioFrameRenderer {
    static func render(_ image: CGImage, config: StudioFrameConfig) -> CGImage? {
        guard config.isActive else { return image }

        let pad = CGFloat(max(0, min(config.padding, 240)))
        let outWidth = image.width + Int(pad * 2)
        let outHeight = image.height + Int(pad * 2)

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: nil,
            width: outWidth,
            height: outHeight,
            bitsPerComponent: 8,
            bytesPerRow: outWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // 1. Draw Backdrop
        context.clear(CGRect(x: 0, y: 0, width: outWidth, height: outHeight))

        if let (startColor, endColor) = config.backdrop.gradientColors {
            let colors = [startColor.cgColor, endColor.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: CGFloat(outHeight)),
                    end: CGPoint(x: CGFloat(outWidth), y: 0),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        } else if let solid = config.backdrop.solidColor {
            context.setFillColor(solid.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
        }
        // If config.backdrop == .transparent, backdrop remains fully cleared (alpha = 0).

        // 2. Composite image with shadow and corner radius
        context.saveGState()

        if config.shadowRadius > 0 && pad > 0 {
            let blur = CGFloat(config.shadowRadius)
            let shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
            context.setShadow(
                offset: CGSize(width: 0, height: -max(2, blur * 0.25)),
                blur: blur,
                color: shadowColor
            )
        }

        context.beginTransparencyLayer(auxiliaryInfo: nil)

        let imageRect = CGRect(x: pad, y: pad, width: CGFloat(image.width), height: CGFloat(image.height))
        let cornerRadius = CGFloat(max(0, config.cornerRadius))

        let roundedPath: CGPath
        if cornerRadius > 0 {
            roundedPath = CGPath(roundedRect: imageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        } else {
            roundedPath = CGPath(rect: imageRect, transform: nil)
        }

        context.saveGState()
        context.addPath(roundedPath)
        context.clip()
        context.draw(image, in: imageRect)
        context.restoreGState()

        // 1px subtle sheen border
        if cornerRadius > 0 {
            context.saveGState()
            context.addPath(roundedPath)
            context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16))
            context.setLineWidth(1.0)
            context.strokePath()
            context.restoreGState()
        }

        context.endTransparencyLayer()
        context.restoreGState()

        return context.makeImage()
    }
}
