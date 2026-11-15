import SwiftUI
import MyNotchCore
@_exported import NotchUI
#if os(macOS)
import AppKit
#endif

public typealias DashboardThemeStore = NotchUI.DashboardThemeStore
public typealias DashboardThemeStyle = NotchUI.DashboardThemeStyle

extension Color {
    public init(glass: GlassRGBA) {
        self.init(red: glass.r / 255.0, green: glass.g / 255.0, blue: glass.b / 255.0, opacity: glass.a)
    }
}

/// Dynamic, developer-ergonomic theme tokens adapting to the selected `DashboardThemeStyle`.
/// Anti-AI-Slop strict compliance: Clean Slate/Zinc palette, crisp typography, mechanical curves, subtle shadows.
public enum DashboardTheme {
    @MainActor
    public static var currentStyle: DashboardThemeStyle {
        DashboardThemeStore.shared.style
    }

    // Canvas & Containers

    /// Luminous white acrylic wash applied behind windows to guarantee >= 215 luma over dark desktop wallpapers.
    @MainActor
    public static var rootWash: Color {
        switch currentStyle {
        case .softUI, .stripeLight:
            return Color.clear
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.rootWash)
        }
    }

    @MainActor
    public static var canvasBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 234/255, green: 239/255, blue: 245/255) // #eaeff5 (Slate 150 ấm dịu, chênh lệch > 8% so với thẻ trắng)
        case .liquidGlass:
            return Color.clear // Cho phép nhìn thấu kính mờ xuyên qua cửa sổ desktop
        case .stripeLight:
            return Color(red: 244/255, green: 246/255, blue: 249/255) // #f4f6f9 (Slate Fintech crisp)
        }
    }

    @MainActor
    public static var cardBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color.white
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.card) // Kính phẳng sáng rực rỡ (white 0.88)
        case .stripeLight:
            return Color.white
        }
    }

    @MainActor
    public static var cardBackgroundHover: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 241/255, green: 245/255, blue: 249/255) // #f1f5f9
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.cardHover)
        case .stripeLight:
            return Color(red: 248/255, green: 250/255, blue: 252/255) // #f8fafc
        }
    }

    @MainActor
    public static var sidebarBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 226/255, green: 232/255, blue: 240/255) // #e2e8f0 (Slate 200)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.sidebarFill) // Kính mờ thanh thoát (white 0.60)
        case .stripeLight:
            return Color.white // Trắng tinh khiết chuẩn Stripe
        }
    }

    @MainActor
    public static var headerBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color.white
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.headerFill) // Kính mờ header (white 0.55)
        case .stripeLight:
            return Color.white
        }
    }

    @MainActor
    public static var rowBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color.white
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.row) // Lớp hàng sáng (white 0.70)
        case .stripeLight:
            return Color.white
        }
    }

    @MainActor
    public static var insetBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 234/255, green: 239/255, blue: 245/255) // #eaeff5 (Khớp y hệt canvasBackground cũ)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.inset) // Lòng ô nhập / tag (slate 900 0.045)
        case .stripeLight:
            return Color(red: 244/255, green: 246/255, blue: 249/255) // #f4f6f9 (Khớp y hệt canvasBackground cũ)
        }
    }

    @MainActor
    public static var insetBorder: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 226/255, green: 232/255, blue: 240/255)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.insetBorder) // Viền ô nhập (slate 500 0.28)
        case .stripeLight:
            return Color(red: 203/255, green: 213/255, blue: 225/255)
        }
    }

    @MainActor
    public static var controlBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color.white
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.control) // Nút bấm / segment active (white 0.90)
        case .stripeLight:
            return Color.white
        }
    }

    @MainActor
    public static var controlBorder: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 226/255, green: 232/255, blue: 240/255)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.controlBorder) // Viền nút bấm (slate 500 0.30)
        case .stripeLight:
            return Color(red: 203/255, green: 213/255, blue: 225/255)
        }
    }

    @MainActor
    public static var segmentTrackBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 226/255, green: 232/255, blue: 240/255)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.segmentTrack) // Rãnh switcher (slate 900 0.08)
        case .stripeLight:
            return Color(red: 241/255, green: 245/255, blue: 249/255)
        }
    }

    @MainActor
    public static var chipBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 226/255, green: 232/255, blue: 240/255)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.chip) // Nền tag/chip (slate 500 0.16)
        case .stripeLight:
            return Color(red: 241/255, green: 245/255, blue: 249/255)
        }
    }

    @MainActor
    public static var navActiveBackground: Color {
        switch currentStyle {
        case .softUI:
            return Color.white
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.navActive)
        case .stripeLight:
            return Color(red: 239/255, green: 246/255, blue: 255/255)
        }
    }

    @MainActor
    public static var hairlineBorder: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 226/255, green: 232/255, blue: 240/255) // #e2e8f0
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.outerEdgeBorder) // Viền ngoài slate 900 0.10
        case .stripeLight:
            return Color(red: 203/255, green: 213/255, blue: 225/255) // #cbd5e1 (Slate 300 sắc nét)
        }
    }

    @MainActor
    public static var specularBorder: Color {
        switch currentStyle {
        case .softUI, .stripeLight:
            return Color.clear
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.specularBorder) // Viền specular trắng 0.95
        }
    }

    @MainActor
    public static var subtleDivider: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 226/255, green: 232/255, blue: 240/255)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.separator) // #0f172a 0.10
        case .stripeLight:
            return Color(red: 226/255, green: 232/255, blue: 240/255)
        }
    }

    @MainActor
    public static var separator: Color {
        subtleDivider
    }

    // Typography & Content (Crisp High-Contrast)
    @MainActor
    public static var textPrimary: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 15/255, green: 23/255, blue: 42/255) // #0f172a (Slate 900)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.textPrimary) // #0f172a (Contrast >= 12:1)
        case .stripeLight:
            return Color(red: 30/255, green: 41/255, blue: 59/255) // #1e293b (Slate 800)
        }
    }

    @MainActor
    public static var textSecondary: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 71/255, green: 85/255, blue: 105/255) // #475569 (Slate 600)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.textSecondary) // #334155 (Slate 700, Contrast >= 7:1 AAA)
        case .stripeLight:
            return Color(red: 71/255, green: 85/255, blue: 105/255)
        }
    }

    @MainActor
    public static var textMuted: Color {
        switch currentStyle {
        case .softUI:
            return Color(red: 148/255, green: 163/255, blue: 184/255) // #94a3b8 (Slate 400)
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.textMuted) // #475569 (Slate 600, Contrast >= 4.5:1 AA)
        case .stripeLight:
            return Color(red: 148/255, green: 163/255, blue: 184/255)
        }
    }

    @MainActor
    public static var accentText: Color {
        switch currentStyle {
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.accentText)
        default:
            return Color(red: 37/255, green: 99/255, blue: 235/255)
        }
    }

    @MainActor
    public static var successText: Color {
        switch currentStyle {
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.successText)
        default:
            return Color(red: 5/255, green: 150/255, blue: 105/255) // Emerald 600 (Gốc chuẩn DashboardComponents)
        }
    }

    @MainActor
    public static var warningText: Color {
        switch currentStyle {
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.warningText)
        default:
            return Color(red: 217/255, green: 119/255, blue: 6/255) // Amber 600 (Gốc chuẩn DashboardComponents)
        }
    }

    @MainActor
    public static var dangerText: Color {
        switch currentStyle {
        case .liquidGlass:
            return Color(glass: DashboardGlassSpec.dangerText)
        default:
            return Color(red: 220/255, green: 38/255, blue: 38/255) // Red 600 (Gốc chuẩn DashboardComponents)
        }
    }

    // Geometry & Layout
    @MainActor
    public static var cardCornerRadius: CGFloat {
        switch currentStyle {
        case .softUI: return 16.0 // Scandinavian bồng bềnh
        case .liquidGlass: return 12.0 // macOS native glass
        case .stripeLight: return 6.0 // Precision Fintech mechanical
        }
    }

    // Vibrant Semantic Accents for Data & Indicators
    public static let statusNormal = Color(red: 16/255, green: 185/255, blue: 129/255) // #10b981 (Emerald 500)
    public static let statusDegraded = Color(red: 245/255, green: 158/255, blue: 11/255) // #f59e0b (Amber 500)
    public static let statusCritical = Color(red: 239/255, green: 68/255, blue: 68/255) // #ef4444 (Red 500)
    public static let statusNeutral = Color(red: 100/255, green: 116/255, blue: 139/255) // #64748b (Slate 500)
    public static let infoAccent = Color(red: 37/255, green: 99/255, blue: 235/255) // #2563eb (Blue 600)

    // Module Specific Color Accents
    public static let batteryGreen = Color(red: 16/255, green: 185/255, blue: 129/255)
    public static let hardwareCoral = Color(red: 249/255, green: 115/255, blue: 22/255)
    public static let todoBlue = Color(red: 14/255, green: 165/255, blue: 233/255)
    public static let habitViolet = Color(red: 139/255, green: 92/255, blue: 246/255)

    // Byte Formatting Utility
    public static func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

public struct DashboardCardModifier: ViewModifier {
    public var padding: CGFloat = 16
    public var customCornerRadius: CGFloat? = nil

    @ObservedObject private var themeStore = DashboardThemeStore.shared

    private var effectiveCornerRadius: CGFloat {
        customCornerRadius ?? DashboardTheme.cardCornerRadius
    }

    public func body(content: Content) -> some View {
        let style = themeStore.style
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
                    .fill(DashboardTheme.cardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous))
            .shadow(
                color: style == .softUI
                    ? Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.08)
                    : (style == .liquidGlass ? Color.black.opacity(0.05) : Color.black.opacity(0.04)),
                radius: style == .softUI ? 12 : (style == .liquidGlass ? 10 : 2),
                x: 0,
                y: style == .softUI ? 4 : (style == .liquidGlass ? 3 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
                    .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
            )
            .overlay(
                Group {
                    if style == .liquidGlass {
                        RoundedRectangle(cornerRadius: max(effectiveCornerRadius - 0.5, 0), style: .continuous)
                            .inset(by: 0.5)
                            .stroke(DashboardTheme.specularBorder, lineWidth: 1)
                    }
                }
            )
    }
}

extension View {
    public func dashboardCard(padding: CGFloat = 16, cornerRadius: CGFloat? = nil) -> some View {
        modifier(DashboardCardModifier(padding: padding, customCornerRadius: cornerRadius))
    }

    @MainActor
    public func hairlineBorder() -> some View {
        overlay(
            Rectangle()
                .stroke(DashboardTheme.hairlineBorder, lineWidth: 1)
        )
    }
}

#if os(macOS)
/// Native macOS Visual Effect View providing real desktop blur and vibrancy behind the window.
public struct DashboardVisualEffectBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .underWindowBackground
    public var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    public var state: NSVisualEffectView.State = .active

    public init(
        material: NSVisualEffectView.Material = .underWindowBackground,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.appearance = NSAppearance(named: .aqua)
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.appearance = NSAppearance(named: .aqua)
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
#endif
