import SwiftUI

/// How the notch is drawn.
nonisolated public enum NotchLook: String, Codable, Sendable, CaseIterable {
    /// Black, which is also what the hardware notch is, so the two join. The look the notch always had.
    case classic
    /// Liquid Glass (macOS 26): the notch, its bubbles and what opens from it are one family of glass shapes.
    case liquidGlass
}

/// What the notch's shape is filled with right now, which is the look and, for the classic one, the state.
nonisolated public enum NotchSurface: Equatable, Sendable {
    /// Opaque black.
    case solid
    /// The classic look's "Kính mờ": a blur under a veil of black behind the open notch.
    case material
    /// Liquid Glass, with a hint of the accent in it when `tinted`.
    case liquidGlass(tinted: Bool)

    /// The surface for `look` in `state`. Liquid Glass is glass in every state, the collapsed notch included, and supersedes
    /// the classic blur whichever way that is set; the classic look is black, and blurred only while expanded.
    public static func resolve(look: NotchLook, classicGlass: Bool, tinted: Bool, state: NotchState) -> NotchSurface {
        switch look {
        case .liquidGlass: .liquidGlass(tinted: tinted)
        case .classic: NotchTheme.showsGlass(enabled: classicGlass, state: state) ? .material : .solid
        }
    }

    public var isLiquidGlass: Bool {
        if case .liquidGlass = self { true } else { false }
    }
}

/// Which foreground the notch's own text and glyphs use: the fixed white of the black notch, or the system's styles, which
/// are vibrant on glass and follow the appearance instead of assuming what is behind them.
nonisolated enum NotchForeground: Equatable, Sendable {
    case fixed
    case vibrant
}

nonisolated extension NotchSurface {
    var foreground: NotchForeground { isLiquidGlass ? .vibrant : .fixed }
}

extension NotchSurface {
    /// The style of the notch's own primary text and glyphs: white on black, the system's primary style on glass. It is the
    /// system's hierarchical style, so it follows the appearance and keeps the vibrancy glass gives it.
    public var primaryStyle: AnyShapeStyle {
        foreground == .vibrant ? AnyShapeStyle(.primary) : AnyShapeStyle(NotchTokens.primaryText)
    }

    /// The same for secondary text and glyphs.
    public var secondaryStyle: AnyShapeStyle {
        foreground == .vibrant ? AnyShapeStyle(.secondary) : AnyShapeStyle(NotchTokens.secondaryText)
    }
}
