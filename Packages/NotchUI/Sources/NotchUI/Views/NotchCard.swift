import SwiftUI

/// How a card, a field, a chip or the selected tab is drawn, as a value, so a test reads what the view draws. It depends on the
/// surface and on the debug switches, and only on glass: the classic notch always gets the wash it has always had.
nonisolated struct NotchCardPlan: Equatable, Sendable {
    enum Fill: Equatable, Sendable {
        /// `NotchTokens.fill(opacity)` behind the shape: today's wash, on the classic notch and with `cards=fill`.
        case wash(Double)
        /// What marks the selection with no glass: the accent at `NotchTokens.selectionOpacity`, and on glass also a rim of the
        /// label colour (the selected tab's capsule as it is today).
        case selectedWash(rim: Bool)
        /// A glass shape of its own.
        case glass(Glass)
        /// A solid white tile, for the selection with `selected=white`: `notchCard` draws its content in black.
        case onTile
    }

    let fill: Fill

    /// How much of the accent tints a selected chip's or tab's glass: more than the notch's own hint, since it has to mark a state.
    static let selectedTintOpacity = 0.5

    /// The card for `surface` under `switches`. `fill` is the wash's opacity (a module keeps its own, 0.08 being the usual);
    /// `selected` is a chip or tab that is on; `interactive` is for glass that is a control.
    static func resolve(
        surface: NotchSurface, switches: NotchGlassSwitches, accent: Color, fill: Double = 0.08, selected: Bool = false,
        interactive: Bool = false
    ) -> NotchCardPlan {
        guard surface.isLiquidGlass, switches.cards == .glass else {
            return NotchCardPlan(fill: selected ? .selectedWash(rim: surface.isLiquidGlass) : .wash(fill))
        }
        if selected, switches.selected == .white { return NotchCardPlan(fill: .onTile) }
        var glass = switches.variant.glass
        if selected { glass = glass.tint(accent.opacity(selectedTintOpacity)) }
        return NotchCardPlan(fill: .glass(interactive ? glass.interactive() : glass))
    }

    /// The radius of a shape inside another one that is `inset` away from its edge: the outer radius less that gap, so the two
    /// curves are concentric. Never below 0.
    static func concentricRadius(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, 0)
    }
}

extension View {
    /// Draws the view on a card in `shape`: a wash of the text colour at `fill` behind it, which is exactly
    /// `.background(NotchTokens.fill(fill), in: shape)`, so adopting it changes nothing on the classic notch or in the classic
    /// look. With Liquid Glass and the debug switch `debug.glass.cards=glass` the card is a glass shape of its own, of the same
    /// variant as the notch, that floats on the notch's glass (the content of the open notch has an inner container for this).
    ///
    /// `selected` marks a chip or tab that is on: the accent wash on the classic notch, glass tinted with the accent or a solid
    /// white tile (`debug.glass.selected`) with glass cards; on the white tile the content is drawn in black. `interactive` is
    /// for a card that is a control, so its glass reacts to the pointer.
    ///
    /// For concentric corners give a card on the open notch the notch's bottom radius less the padding between the two
    /// (24 - 14 = 10), and a shape inside a card the card's radius less its own padding (`NotchCardPlan.concentricRadius`).
    public func notchCard(in shape: some Shape, fill: Double = 0.08, interactive: Bool = false, selected: Bool = false) -> some View {
        modifier(NotchCardModifier(shape: shape, fill: fill, interactive: interactive, selected: selected))
    }
}

private struct NotchCardModifier<S: Shape>: ViewModifier {
    let shape: S
    let fill: Double
    let interactive: Bool
    let selected: Bool
    @Environment(\.notchSurface) private var surface
    @Environment(\.notchAccent) private var accent
    @Environment(\.notchGlassSwitches) private var switches

    func body(content: Content) -> some View {
        let plan = NotchCardPlan.resolve(
            surface: surface, switches: switches, accent: accent, fill: fill, selected: selected, interactive: interactive
        )
        switch plan.fill {
        case .wash(let opacity):
            content.background(NotchTokens.fill(opacity), in: shape)
        case .selectedWash(let rim):
            content.background {
                shape.fill(accent.opacity(NotchTokens.selectionOpacity))
                    .overlay { if rim { shape.stroke(.primary.opacity(NotchTokens.glassSelectionRim), lineWidth: 2).clipShape(shape) } }
            }
        case .glass(let glass):
            content.glassEffect(glass, in: shape)
        case .onTile:
            content.foregroundStyle(Color.black).background(Color.white, in: shape)
        }
    }
}

/// Holds the cards, chips and fields of the open notch in a container of their own when they are glass, apart from the notch's
/// container, with `spacing` as their blend distance; nothing at all when `spacing` is nil, so the tree is then what it was.
/// Its content is as big as the space it is given, like the notch's family, so the container does not shrink it.
struct NotchCardGroup<Content: View>: View {
    let spacing: CGFloat?
    let content: Content

    init(spacing: CGFloat?, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if let spacing {
            GlassEffectContainer(spacing: spacing) { content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }
        } else {
            content
        }
    }
}
