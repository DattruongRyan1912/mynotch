import SwiftUI

/// Shared look of the notch. Modules use these instead of hard-coded values.
public enum NotchTokens {
    public static let background = Color.black
    public static let accent = Color(red: 0.49, green: 0.36, blue: 1.0)
    /// Text on the notch. White on the classic notch, which is black; on Liquid Glass the system's primary colour, which follows
    /// the appearance, so text keeps its contrast on glass that is light or dark (see `NotchLookState`).
    public static var primaryText: Color { NotchLookState.current.isGlass ? .primary : .white }
    /// Secondary text, likewise: white at 0.6, or the system's secondary colour on glass.
    public static var secondaryText: Color { NotchLookState.current.isGlass ? .secondary : .white.opacity(0.6) }
    /// A wash of the text colour at `opacity`, for what a module draws behind or around its text: a card, a hovered row, a divider,
    /// an outline. White on the classic notch; on Liquid Glass the system's primary colour, so the wash is dark on light glass and
    /// light on dark glass and the text over it keeps its contrast. Read it in a `body`, like the text tokens.
    public static func fill(_ opacity: Double) -> Color {
        NotchLookState.current.isGlass ? Color.primary.opacity(opacity) : Color.white.opacity(opacity)
    }
    /// Inner padding of the open notch; `nonisolated` because the geometry's maths reads it.
    nonisolated public static let padding: CGFloat = 14
    /// Opacity of the accent behind the selected tab; `nonisolated` because the accent's legibility on black is worked out from it.
    nonisolated public static let selectionOpacity: CGFloat = 0.32
    /// On Liquid Glass the selected tab's capsule also has a rim of the primary label colour at this opacity (black on light glass,
    /// white on dark), so an accent as light as the glass (yellow, orange, green on a bright wallpaper) still marks the selection.
    nonisolated public static let glassSelectionRim: CGFloat = 0.3
    /// How much of the accent tints the Liquid Glass when the user asks for it: a hint of it, not a coat.
    nonisolated public static let glassTintOpacity: CGFloat = 0.25
    /// Space left and right of an activity's strip under the collapsed notch, inside the notch's body.
    nonisolated public static let stripPadding: CGFloat = 12
    /// The one animation of the notch's size and shape; every state change moves it with this spring.
    public static let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)
    /// A bubble beside the collapsed notch comes and goes at this fraction of its size, never from nothing.
    static let bubbleAppearScale = 0.4
    /// An activity's `minimal` view inside its bubble.
    static let bubbleIconSize: CGFloat = 18
    /// Icon of a row of the list of all activities.
    static let listIconSize: CGFloat = 16

    /// Content entering the notch follows the shape a moment later on the same spring.
    static let enter = spring.delay(0.08)
    /// Content leaving the notch is gone quickly, so it does not hang on while the shape is already moving.
    static let leave = Animation.easeOut(duration: 0.1)
    /// One tab replacing another in an open notch: a quick dissolve instead of the spring's half-second tail,
    /// which kept both tabs on screen while the shape resized.
    static let swap = Animation.easeInOut(duration: 0.14)
}

extension View {
    /// For a view that draws on a background of its own that is always dark (a floating chip, the lyrics panel): gives it the dark
    /// colour scheme, in which the text tokens are light whatever the look is. Without it, on Liquid Glass in the light appearance
    /// the tokens are the system's primary and secondary colours, which are black there, and text on a black background is lost.
    /// Not needed inside the notch itself, nor on a system material.
    public func notchOnDarkBackground() -> some View {
        environment(\.colorScheme, .dark)
    }

    /// The colour scheme for the controls and default text of a module's tab: dark on the classic notch, which is black whatever
    /// the system appearance is, and the system's own on Liquid Glass, so the controls and the text tokens follow the glass.
    /// Use it where a tab used to set `.environment(\.colorScheme, .dark)`, which on glass would turn text white on light glass.
    public func notchColorScheme() -> some View {
        modifier(NotchColorScheme())
    }
}

private struct NotchColorScheme: ViewModifier {
    @Environment(\.colorScheme) private var system

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, NotchLookState.current.isGlass ? system : .dark)
    }
}
