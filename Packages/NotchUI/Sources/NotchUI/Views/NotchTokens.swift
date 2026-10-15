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
    public static let stripPadding: CGFloat = 12
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
