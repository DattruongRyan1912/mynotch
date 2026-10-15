import SwiftUI

extension EnvironmentValues {
    /// What the notch is drawn on right now: black, the classic blur or Liquid Glass. Set by the notch's root view for
    /// everything in it, and the thing to read for a foreground that should work on both (`NotchSurface.primaryStyle`). Outside
    /// a notch (a preview, a test, a floating window that did not set it) it is black.
    @Entry public var notchSurface: NotchSurface = .solid

    /// The namespace of the glass family: the notch and its bubbles name their shapes in it (`NotchGlassID`) so SwiftUI morphs
    /// the ones that keep their name. Nil outside the notch's root view and in the classic look.
    @Entry var notchGlassNamespace: Namespace.ID?

    /// The glass the notch's root view asked for, which its bubbles draw from. Nothing outside the notch's root view.
    @Entry var notchGlassPlan: NotchGlassPlan = .none
}

/// Names the glass shapes of the notch's family inside the root view's namespace. A shape that keeps its name is morphed by
/// SwiftUI (the notch as it opens, closes and grows a strip, a bubble when the others around it come and go); a name that
/// appears or disappears is a shape that comes out of its neighbours or melts back into them.
nonisolated enum NotchGlassID: Hashable, Sendable {
    /// The notch is one shape in every state: closed, collapsed with a strip or the list, open, a toast. So opening it is the
    /// same glass growing, not one glass replaced by another.
    case notch
    /// A bubble is named after its activity (`ActivitySlot.id`), and the "+N" bubble keeps its name while its number changes.
    case bubble(String)
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

/// What glass the notch asks for, as a value: whether the notch and its bubbles share a container, and for each shape its name
/// in the morph namespace and its `Glass`. The root view and the bubbles draw from it, so a test that reads it reads what is
/// drawn. It does not depend on the notch's state: the notch is one shape whose glass is the same closed, collapsed, open or
/// showing a toast, so nothing about it is rebuilt while it morphs.
nonisolated struct NotchGlassPlan: Equatable, Sendable {
    /// One glass shape: its name in the namespace and what it is made of.
    struct Shape: Equatable, Sendable {
        let id: NotchGlassID
        let glass: Glass
    }

    /// No glass at all: the classic look.
    static let none = NotchGlassPlan()

    /// How close two glass shapes of the family have to be for them to melt into each other. A bit below the gap between a
    /// bubble and what is beside it (6 pt), and below the nearest the notch's top ear comes to its first bubble (5 pt on the
    /// smallest notch, 6.6 on the 14" MacBook's), so at rest the shapes stay apart and they blend only while one moves to or from
    /// the other.
    static let containerSpacing: CGFloat = 4

    /// Whether the notch and its bubbles are wrapped in one `GlassEffectContainer`.
    let usesContainer: Bool
    let notch: Shape?
    /// The bubbles' shapes, in the order of the bubbles.
    let bubbles: [Shape]

    var containerSpacing: CGFloat? { usesContainer ? Self.containerSpacing : nil }
    var shapes: [Shape] { (notch.map { [$0] } ?? []) + bubbles }

    private init() {
        (usesContainer, notch, bubbles) = (false, nil, [])
    }

    /// The plan for `surface` with a bubble for each of `bubbleIDs` (the `ActivitySlot.id`s). The notch's glass is not
    /// interactive: it is a surface that holds controls, not a control. A bubble is a button, so its glass is.
    init(surface: NotchSurface, bubbleIDs: [String], accent: Color) {
        guard let notchGlass = surface.glass(accent: accent, interactive: false), let bubbleGlass = surface.glass(accent: accent, interactive: true) else {
            self = .none
            return
        }
        usesContainer = true
        notch = Shape(id: .notch, glass: notchGlass)
        bubbles = bubbleIDs.map { Shape(id: .bubble($0), glass: bubbleGlass) }
    }

    /// The shape of the bubble of activity `id`, if the plan has one.
    func bubble(id: String) -> Shape? {
        bubbles.first { $0.id == .bubble(id) }
    }
}

extension View {
    /// Draws the glass `planned` in `shape` behind the view, with its name in `namespace` when there is one, so it takes part in
    /// the family's morph; the view itself when nothing is planned. Applied after the view's size is set, so the glass is as big
    /// as the view and follows its animation.
    @ViewBuilder func notchGlass<S: Shape>(_ planned: NotchGlassPlan.Shape?, in shape: S, namespace: Namespace.ID? = nil) -> some View {
        if let planned {
            if let namespace {
                glassEffect(planned.glass, in: shape).glassEffectID(planned.id, in: namespace)
            } else {
                glassEffect(planned.glass, in: shape)
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
            .notchGlass(NotchGlassPlan(surface: surface, bubbleIDs: [], accent: accent).notch, in: shape)
    }
}

/// Wraps the notch and its bubbles in the container that lets their glass blend and morph as one family, when the plan says
/// so. In the classic look it adds nothing: the content is exactly what it was.
struct NotchGlassFamily<Content: View>: View {
    let plan: NotchGlassPlan
    let content: Content

    init(_ plan: NotchGlassPlan, @ViewBuilder content: () -> Content) {
        self.plan = plan
        self.content = content()
    }

    var body: some View {
        if let spacing = plan.containerSpacing {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
