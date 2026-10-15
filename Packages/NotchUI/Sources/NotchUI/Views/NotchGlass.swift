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
    /// The `Glass` this surface draws, nil for the black and the classic blur. The regular variant unless `variant` says clear
    /// (a debug switch), which adapts to what is behind it, tinted with `accent` at low strength when the user asks for it.
    func glass(accent: Color, interactive: Bool, variant: NotchGlassVariant = .regular) -> Glass? {
        guard case .liquidGlass(let tinted) = self else { return nil }
        var glass = variant.glass
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

    /// The notch's surface when an `NSGlassEffectView` draws it (the AppKit host) instead of `glassEffect`.
    struct AppKitSurface: Equatable, Sendable {
        let variant: NotchGlassVariant
        /// The accent at low strength when the user asks for the tint.
        let tint: Color?
    }

    /// No glass at all: the classic look.
    static let none = NotchGlassPlan()

    /// How close two glass shapes of the family have to be for them to melt into each other. A bit below the gap between a
    /// bubble and what is beside it (6 pt), and below the nearest the notch's top ear comes to its first bubble (5 pt on the
    /// smallest notch, 6.6 on the 14" MacBook's), so at rest the shapes stay apart and they blend only while one moves to or from
    /// the other.
    static let containerSpacing: CGFloat = 4

    /// How close two cards, chips or fields in the inner container (below) have to be to melt into each other: a little, so the
    /// ones that sit 6 or 8 pt apart in a module's grid stay apart.
    static let innerContainerSpacing: CGFloat = 2

    /// Whether the notch and its bubbles are wrapped in one `GlassEffectContainer`.
    let usesContainer: Bool
    /// The notch's own shape when `glassEffect` draws it; nil in the AppKit host, which draws it itself (`appKitNotch`).
    let notch: Shape?
    /// The bubbles' shapes, in the order of the bubbles.
    let bubbles: [Shape]
    /// The notch's surface in the AppKit host; nil when `glassEffect` draws it.
    let appKitNotch: AppKitSurface?
    /// How much black goes between the glass and the content, inside the notch's shape.
    let dim: Double
    /// The colour scheme forced on the content (the notch's and the bubbles'), not on the glass; nil leaves the window's own.
    let contentScheme: ColorScheme?
    /// The spacing of the inner `GlassEffectContainer` that holds the cards, chips and fields of the open notch, apart from the
    /// notch's container; nil when they are not glass. See `cardContainerSpacing(surface:switches:)`.
    let cardContainerSpacing: CGFloat?

    var containerSpacing: CGFloat? { usesContainer ? Self.containerSpacing : nil }
    var shapes: [Shape] { (notch.map { [$0] } ?? []) + bubbles }

    private init() {
        (usesContainer, notch, bubbles, appKitNotch, dim, contentScheme, cardContainerSpacing) = (false, nil, [], nil, 0, nil, nil)
    }

    /// The inner container's spacing for cards of `surface` under `switches`: one when the cards are glass on a glass notch.
    ///
    /// Why an inner container. A glass shape inside the content of another glass view (a card in the notch) gets a backdrop of
    /// its own in the layer tree, apart from the notch's, with or without a container around it (a throwaway probe of the layer
    /// tree showed it; nothing here can see what the window server then draws). What the container changes is the grouping: two
    /// cards side by side with no container are one backdrop each (three with the notch's), and in one container they share one
    /// (two with the notch's), and their blend distance is ours to set, below the gap a module leaves between cards. So the content
    /// of the open notch gets one container of its own, not the notch's.
    static func cardContainerSpacing(surface: NotchSurface, switches: NotchGlassSwitches) -> CGFloat? {
        surface.isLiquidGlass && switches.cards == .glass ? innerContainerSpacing : nil
    }

    /// The plan for `surface` with a bubble for each of `bubbleIDs` (the `ActivitySlot.id`s). The notch's glass is not
    /// interactive: it is a surface that holds controls, not a control. A bubble is a button, so its glass is. `switches` are the
    /// debug switches, which only matter on glass: today's behaviour when they are left out.
    init(surface: NotchSurface, bubbleIDs: [String], accent: Color, switches: NotchGlassSwitches = .default) {
        guard let notchGlass = surface.glass(accent: accent, interactive: false, variant: switches.variant),
              let bubbleGlass = surface.glass(accent: accent, interactive: true, variant: switches.variant)
        else {
            self = .none
            return
        }
        usesContainer = true
        switch switches.host {
        case .swiftui:
            notch = Shape(id: .notch, glass: notchGlass)
            appKitNotch = nil
        case .appkit:
            notch = nil
            let tint: Color? = if case .liquidGlass(tinted: true) = surface { accent.opacity(NotchTokens.glassTintOpacity) } else { nil }
            appKitNotch = AppKitSurface(variant: switches.variant, tint: tint)
        }
        bubbles = bubbleIDs.map { Shape(id: .bubble($0), glass: bubbleGlass) }
        dim = switches.dim
        contentScheme = switches.scheme == .dark ? .dark : nil
        cardContainerSpacing = Self.cardContainerSpacing(surface: surface, switches: switches)
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

    /// Forces `scheme` on the view's content when there is one; the view itself otherwise, so the default tree is unchanged.
    @ViewBuilder func notchContentScheme(_ scheme: ColorScheme?) -> some View {
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
    /// Nothing is forced on the content: on glass it keeps the window's colour scheme, as the glass itself follows the system's
    /// appearance. Read `notchSurface` for the `primaryStyle` and `secondaryStyle` that stay readable on both looks. The glass is
    /// drawn by the window server, which needs a window that is not opaque.
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
            .background(NotchBackdrop(surface: surface, bodyHeight: 0))
            .clipShape(shape)
            .notchGlass(NotchGlassPlan(surface: surface, bubbleIDs: [], accent: accent).notch, in: shape)
    }
}

/// Wraps the notch and its bubbles in the container that lets their glass blend and morph as one family, when the plan says
/// so. In the classic look it adds nothing but the frame.
///
/// The content is always as big as the space it is given (the panel), with what it holds at the top centre, in every state. A
/// glass container places each glass shape from the layout of its content, and a notch that is the only thing in it is as big
/// as the notch, which animates: the glass then grew from the content's right edge instead of about the notch's centre. A
/// bubble row as wide as the panel hid this whenever a bubble was there.
struct NotchGlassFamily<Content: View>: View {
    let plan: NotchGlassPlan
    let content: Content

    init(_ plan: NotchGlassPlan, @ViewBuilder content: () -> Content) {
        self.plan = plan
        self.content = content()
    }

    var body: some View {
        let framed = content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        if let spacing = plan.containerSpacing {
            GlassEffectContainer(spacing: spacing) { framed }
        } else {
            framed
        }
    }
}
