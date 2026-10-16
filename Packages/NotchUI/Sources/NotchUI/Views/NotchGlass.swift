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
    /// same glass growing, not one glass replaced by another. (With `tiles` it is the one shape of every state
    /// but the open one, which is made of `tabBar` and `content` instead.)
    case notch
    /// The tab bar's capsule of the open notch, with `tiles`.
    case tabBar
    /// The tile that holds the open tab's content, with `tiles`.
    case content
    /// A bubble is named after its activity (`ActivitySlot.id`), and the "+N" bubble keeps its name while its number changes.
    case bubble(String)
}

nonisolated extension NotchSurface {
    /// The `Glass` this surface draws, nil for the black and the classic blur: the balanced (regular) one, which adapts to what is
    /// behind it, or the clear one when the user chose it, tinted with `accent` at low strength when the user asks for it.
    func glass(accent: Color, interactive: Bool, clarity: NotchGlassClarity = .balanced) -> Glass? {
        guard case .liquidGlass(let tinted) = self else { return nil }
        var glass = clarity.glass
        if tinted { glass = glass.tint(accent.opacity(NotchTokens.glassTintOpacity)) }
        return interactive ? glass.interactive() : glass
    }
}

/// What glass the notch asks for, as a value: whether the notch and its bubbles share a container, and for each shape its name
/// in the morph namespace and its `Glass`. The root view and the bubbles draw from it, so a test that reads it reads what is
/// drawn. The notch's own shape is glass in every state and in every shape, because only what is inside a view that carries the
/// glass is drawn above it: the collapsed notch's text and a toast's content are inside it, and with the glass behind the view
/// instead they sat under the glass and were blurred. With the usual shape (`slab`) it does not depend on the notch's state, so
/// nothing about it is rebuilt while it morphs. With `tiles` the open notch's own glass is `Glass.identity` (nothing) and the
/// tab bar's capsule and the content's tile, which are glass in every state and sit inside the collapsed notch while it is not
/// open, come out of it.
nonisolated struct NotchGlassPlan: Equatable, Sendable {
    /// One glass shape: its name in the namespace and what it is made of.
    struct Shape: Equatable, Sendable {
        let id: NotchGlassID
        let glass: Glass
    }

    /// With `tiles`: the tab bar's capsule and the tile that holds the tab's content. Their glass is the notch's in every state, so
    /// the views, and what they hold, are the same ones as the notch opens and closes; whether they are out of the notch or inside
    /// it is a matter of their frames (`NotchTilesLayout`).
    struct Tiles: Equatable, Sendable {
        let tabBar: Shape
        let content: Shape
        /// The notch is open: its own glass is `Glass.identity`, and the tiles are where they were made to be.
        let isOpen: Bool
    }

    /// No glass at all: the classic look.
    static let none = NotchGlassPlan()

    /// How close two glass shapes of the family have to be for them to melt into each other. A bit below the gap between a
    /// bubble and what is beside it (6 pt), and below the nearest the notch's top ear comes to its first bubble (5 pt on the
    /// smallest notch, 6.6 on the 14" MacBook's), so at rest the shapes stay apart and they blend only while one moves to or from
    /// the other.
    static let containerSpacing: CGFloat = 4

    /// The gap between two tiles of the open notch (the tab bar's capsule and the content's tile): wider than `containerSpacing`,
    /// so they do not melt into each other, and it is where the desktop shows.
    static let tileGap: CGFloat = 8

    /// What a tile holds is this far from its edge.
    static let tilePadding: CGFloat = 8

    /// The tab bar's capsule is this far from the tab bar's icons, sideways and up and down.
    static let tabBarInset = CGSize(width: 8, height: 3)

    /// With `tiles` the open notch has no fill, but a window that is transparent where it is not drawn lets a click in a gap fall
    /// through to the app behind. A black layer this faint over the whole notch (under 3 levels of 255, which no one can see) keeps
    /// the gaps part of the window.
    static let hitOpacity = 0.01

    /// The radius of a shape inside another one that is `inset` away from its edge: the outer radius less that gap, so the two
    /// curves are concentric. Never below 0.
    static func concentricRadius(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, 0)
    }

    let shape: NotchGlassShape
    /// Whether the notch and its bubbles are wrapped in one `GlassEffectContainer`.
    let usesContainer: Bool
    /// The notch's own shape: nil only in the classic look. With `tiles` its glass is `Glass.identity` while the notch is open.
    let notch: Shape?
    /// The bubbles' shapes, in the order of the bubbles.
    let bubbles: [Shape]
    /// The tab bar's capsule and the content's tile; nil unless the shape is `tiles`.
    let tiles: Tiles?
    /// The black layer under the open notch, inside its whole shape: with `tiles` and the notch open, the faint veil that keeps the
    /// gaps part of the window; nothing otherwise.
    let veil: Double

    var containerSpacing: CGFloat? { usesContainer ? Self.containerSpacing : nil }
    var shapes: [Shape] { (notch.map { [$0] } ?? []) + bubbles + (tiles.map { [$0.tabBar, $0.content] } ?? []) }

    /// Whether the notch's own glass draws anything right now.
    var panelHasGlass: Bool { notch.map { $0.glass != .identity } ?? false }

    private init() {
        (shape, usesContainer, notch, bubbles, tiles, veil) = (.slab, false, nil, [], nil, 0)
    }

    /// The plan for `surface` with a bubble for each of `bubbleIDs` (the `ActivitySlot.id`s), in `style`, for the notch open or not.
    /// The notch's glass is not interactive: it is a surface that holds controls, not a control. A bubble is a button, so its glass
    /// is.
    init(surface: NotchSurface, bubbleIDs: [String], accent: Color, style: NotchGlassStyle = .default, isOpen: Bool = false) {
        guard let notchGlass = surface.glass(accent: accent, interactive: false, clarity: style.clarity),
              let bubbleGlass = surface.glass(accent: accent, interactive: true, clarity: style.clarity)
        else {
            self = .none
            return
        }
        shape = style.shape
        usesContainer = true
        bubbles = bubbleIDs.map { Shape(id: .bubble($0), glass: bubbleGlass) }
        if style.shape == .tiles {
            notch = Shape(id: .notch, glass: isOpen ? .identity : notchGlass)
            tiles = Tiles(
                tabBar: Shape(id: .tabBar, glass: notchGlass), content: Shape(id: .content, glass: notchGlass), isOpen: isOpen
            )
            veil = isOpen ? Self.hitOpacity : 0
        } else {
            notch = Shape(id: .notch, glass: notchGlass)
            tiles = nil
            veil = 0
        }
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
