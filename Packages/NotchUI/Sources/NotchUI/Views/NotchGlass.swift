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
    /// same glass growing, not one glass replaced by another. (With the debug panel `tiles` it is the one shape of every state
    /// but the open one, which is made of `tabBar` and `content` instead.)
    case notch
    /// The tab bar's capsule of the open notch, with the debug panel `tiles`.
    case tabBar
    /// The tile that holds the open tab's content, with the debug panel `tiles`.
    case content
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
/// drawn. With the usual panel (`slab`) it does not depend on the notch's state: the notch is one shape whose glass is the same
/// closed, collapsed, open or showing a toast, so nothing about it is rebuilt while it morphs. With the debug panel `tiles` the
/// open notch is made of other shapes instead (`tiles`), and only then.
nonisolated struct NotchGlassPlan: Equatable, Sendable {
    /// One glass shape: its name in the namespace and what it is made of.
    struct Shape: Equatable, Sendable {
        let id: NotchGlassID
        let glass: Glass
    }

    /// The open notch with the debug panel `tiles`: the tab bar's capsule and the tile that holds the tab's content. Their glass is
    /// `Glass.identity`, which draws nothing, while the notch is not open (a toast over a tab keeps the tab's views alive and
    /// hidden), so the views and what they hold keep their identity as the notch opens and closes.
    struct Tiles: Equatable, Sendable {
        let tabBar: Shape
        let content: Shape
        /// The open notch draws these: its own shape has no glass, and the strip's shapes sit on the desktop as glass of their own.
        let isOpen: Bool
        /// Opacity of the black layer in each of them, above the glass and below what they hold.
        let dim: Double
    }

    /// No glass at all: the classic look.
    static let none = NotchGlassPlan()

    /// How close two glass shapes of the family have to be for them to melt into each other. A bit below the gap between a
    /// bubble and what is beside it (6 pt), and below the nearest the notch's top ear comes to its first bubble (5 pt on the
    /// smallest notch, 6.6 on the 14" MacBook's), so at rest the shapes stay apart and they blend only while one moves to or from
    /// the other.
    static let containerSpacing: CGFloat = 4

    /// The gap between two tiles of the open notch (the tab bar's capsule, the strip's shapes, the content's tile): wider than
    /// `containerSpacing`, so they do not melt into each other, and it is where the desktop shows.
    static let tileGap: CGFloat = 8

    /// What a tile holds is this far from its edge.
    static let tilePadding: CGFloat = 8

    /// The tab bar's capsule is this far from the tab bar's icons, sideways and up and down.
    static let tabBarInset = CGSize(width: 8, height: 3)

    /// With the panel `tiles` the open notch has no fill, but a window that is transparent where it is not drawn lets a click in a
    /// gap fall through to the app behind. A black layer this faint over the whole notch (under 3 levels of 255, which no one can
    /// see) keeps the gaps part of the window.
    static let hitOpacity = 0.01

    let panel: NotchGlassPanel
    /// Whether the notch and its bubbles are wrapped in one `GlassEffectContainer`.
    let usesContainer: Bool
    /// The notch's own shape: nil in the classic look, and with the panel `tiles` while the notch is open, which has no glass of its own.
    let notch: Shape?
    /// The bubbles' shapes, in the order of the bubbles.
    let bubbles: [Shape]
    /// The open notch's tiles; nil unless the panel is `tiles`.
    let tiles: Tiles?
    /// The black layer the notch's backdrop draws over its glass, inside its whole shape: the dim, or, with tiles when open, the
    /// faint veil that keeps the gaps part of the window (the dim is then in each tile).
    let backdropOpacity: Double
    /// The colour scheme forced on the content (the notch's and the bubbles'), not on the glass; nil leaves the window's own.
    let contentScheme: ColorScheme?

    var containerSpacing: CGFloat? { usesContainer ? Self.containerSpacing : nil }
    var shapes: [Shape] { (notch.map { [$0] } ?? []) + bubbles + (tiles.map { [$0.tabBar, $0.content] } ?? []) }

    /// Whether the strip's shapes are glass on the desktop right now: the open notch with tiles.
    var cardsAreOnTheDesktop: Bool { tiles?.isOpen == true }

    private init() {
        (panel, usesContainer, notch, bubbles, tiles, backdropOpacity, contentScheme) = (.slab, false, nil, [], nil, 0, nil)
    }

    /// The plan for `surface` with a bubble for each of `bubbleIDs` (the `ActivitySlot.id`s), for the notch open or not. The notch's
    /// glass is not interactive: it is a surface that holds controls, not a control. A bubble is a button, so its glass is.
    /// `switches` are the debug switches, which only matter on glass: today's behaviour when they are left out.
    init(surface: NotchSurface, bubbleIDs: [String], accent: Color, switches: NotchGlassSwitches = .default, isOpen: Bool = false) {
        guard let notchGlass = surface.glass(accent: accent, interactive: false, variant: switches.variant),
              let bubbleGlass = surface.glass(accent: accent, interactive: true, variant: switches.variant)
        else {
            self = .none
            return
        }
        panel = switches.panel
        usesContainer = true
        bubbles = bubbleIDs.map { Shape(id: .bubble($0), glass: bubbleGlass) }
        contentScheme = switches.scheme == .dark ? .dark : nil
        if switches.panel == .tiles {
            let open = isOpen
            notch = open ? nil : Shape(id: .notch, glass: notchGlass)
            tiles = Tiles(
                tabBar: Shape(id: .tabBar, glass: open ? notchGlass : .identity),
                content: Shape(id: .content, glass: open ? notchGlass : .identity), isOpen: open, dim: open ? switches.dim : 0
            )
            backdropOpacity = open ? Self.hitOpacity : switches.dim
        } else {
            notch = Shape(id: .notch, glass: notchGlass)
            tiles = nil
            backdropOpacity = switches.dim
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

    /// The notch's own glass drawn behind the view, as a layer of its own, for the debug panel `tiles`: the glass comes and goes
    /// with the open notch, and the view above it, with the whole notch's content, has to keep its identity when it does. Glass
    /// that is a modifier of the view would swap the view for another one each time. `enabled` is constant for a notch (the panel is
    /// `tiles`); the glass inside, when it is `nil`, is nothing. The view itself, with nothing added, when not enabled.
    @ViewBuilder func notchGlassLayer<S: Shape>(
        _ planned: NotchGlassPlan.Shape?, in shape: S, namespace: Namespace.ID?, enabled: Bool
    ) -> some View {
        if enabled {
            background { Color.clear.notchGlass(planned, in: shape, namespace: namespace) }
        } else {
            self
        }
    }

    /// One tile of the open notch: the view on glass in `shape`, with a black layer at the tile's dim between the two. The modifiers
    /// are the same whether the tile has glass or `Glass.identity` (nothing), so the view keeps its identity.
    func notchTile<S: Shape>(_ planned: NotchGlassPlan.Shape, dim: Double, in shape: S, namespace: Namespace.ID?) -> some View {
        background(Color.black.opacity(dim), in: shape).notchGlass(planned, in: shape, namespace: namespace)
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
