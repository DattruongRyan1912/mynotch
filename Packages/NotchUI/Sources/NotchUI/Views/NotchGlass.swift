import SwiftUI

extension EnvironmentValues {
    /// What the notch is drawn on right now: black, the classic blur or Liquid Glass. Set by the notch's root view for
    /// everything in it, and the thing to read for a foreground that should work on both (`NotchSurface.primaryStyle`). Outside
    /// a notch (a preview, a test, a floating window that did not set it) it is black.
    @Entry public var notchSurface: NotchSurface = .solid

    /// The namespace of the glass family: the notch and its bubbles name their shapes in it (`NotchGlassID`) so SwiftUI morphs
    /// the ones that keep their name. Nil outside the notch's root view and in the classic look.
    @Entry var notchGlassNamespace: Namespace.ID?
}

/// Names the glass shapes of the notch's family inside the root view's namespace. A shape that keeps its name is morphed by
/// SwiftUI (the notch as it opens, closes and grows a strip, a bubble when the others around it come and go); a name that
/// appears or disappears is a shape that comes out of its neighbours or melts back into them.
nonisolated enum NotchGlassID: Hashable, Sendable {
    case notch
    case bubble(String)

    /// The notch is one shape in every state: closed, collapsed with a strip or the list, open, a toast. So opening it is
    /// the same glass growing, not one glass replaced by another.
    static func notch(in state: NotchState) -> NotchGlassID { .notch }

    /// A bubble is named after its activity, and the "+N" bubble keeps its name while its number changes (`ActivitySlot.id`).
    @MainActor init(slot: ActivitySlot) {
        self = .bubble(slot.id)
    }
}

nonisolated extension NotchState {
    /// Only the open notch is interactive glass: it is the one surface that is a control in itself, which lifts under the
    /// pointer. The collapsed notch, a toast and the bubbles stay still.
    var wantsInteractiveGlass: Bool {
        if case .open = self { true } else { false }
    }
}

nonisolated extension NotchSurface {
    /// The `Glass` this surface draws, nil for the black and the classic blur. The regular variant, which adapts to what is
    /// behind it, tinted with `accent` at low strength when the user asks for it.
    func glass(accent: Color, interactive: Bool) -> Glass? {
        guard case .liquidGlass(let tinted) = self else { return nil }
        var glass = Glass.regular
        if tinted { glass = glass.tint(accent.opacity(NotchTokens.glassTintOpacity)) }
        return interactive ? glass.interactive() : glass
    }
}

extension View {
    /// Draws the Liquid Glass of `surface` in `shape` behind the view, as part of the glass family when `identity` is given;
    /// the view itself for any other surface. Applied after the view's size is set, so the glass is as big as the view and
    /// follows its animation.
    @ViewBuilder func notchGlass<S: Shape>(
        _ surface: NotchSurface, in shape: S, accent: Color, interactive: Bool = false,
        identity: (id: NotchGlassID, namespace: Namespace.ID)? = nil
    ) -> some View {
        if let glass = surface.glass(accent: accent, interactive: interactive) {
            if let identity {
                glassEffect(glass, in: shape).glassEffectID(identity.id, in: identity.namespace)
            } else {
                glassEffect(glass, in: shape)
            }
        } else {
            self
        }
    }

    /// Gives the content `scheme`, or leaves the environment's alone when it is nil.
    @ViewBuilder func notchColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme { environment(\.colorScheme, scheme) } else { self }
    }

    /// Draws the view on the notch's own surface in `shape`: black in the classic look, Liquid Glass in the other, whichever the
    /// `notchSurface` of its environment says (the notch's root view sets it). For a window or view of MyNotch that wants to
    /// look like the notch, a floating panel for one, which hosts SwiftUI on its own and so has to put the look in itself:
    ///
    ///     content
    ///         .environment(\.notchSurface, interface.surface)
    ///         .environment(\.notchAccent, interface.accent)
    ///         .notchSurface(in: RoundedRectangle(cornerRadius: 18))
    ///
    /// On glass the content is drawn in the dark colour scheme. Read `notchSurface` for the `primaryStyle` and `secondaryStyle`
    /// that stay readable on both. The glass is drawn by the window server, which needs a window that is not opaque.
    public func notchSurface(in shape: some Shape) -> some View {
        modifier(NotchSurfaceModifier(shape: shape))
    }
}

private struct NotchSurfaceModifier<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.notchSurface) private var surface
    @Environment(\.notchAccent) private var accent

    func body(content: Content) -> some View {
        content
            .notchColorScheme(surface.colorScheme)
            .background(NotchBackdrop(surface: surface, bodyHeight: 0))
            .clipShape(shape)
            .notchGlass(surface, in: shape, accent: accent)
    }
}

/// Wraps the notch and its bubbles in the container that lets their glass blend and morph as one family, when the surface is
/// glass. Spacing is the gap between a bubble and what is next to it: shapes closer than that melt into each other while they
/// come and go. In the classic look it adds nothing: the content is exactly what it was.
struct NotchGlassFamily<Content: View>: View {
    let surface: NotchSurface
    let content: Content

    init(_ surface: NotchSurface, @ViewBuilder content: () -> Content) {
        self.surface = surface
        self.content = content()
    }

    var body: some View {
        if surface.isLiquidGlass {
            GlassEffectContainer(spacing: NotchGeometry.bubbleGap) { content }
        } else {
            content
        }
    }
}
