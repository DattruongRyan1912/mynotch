import SwiftUI

extension EnvironmentValues {
    /// Whether what is drawn here sits straight on the desktop (the strip's shapes with the debug panel `tiles`), not on the notch's
    /// glass or inside a tile: glass is only ever drawn there, never inside other glass. Set by what puts a shape on the desktop;
    /// everything else, a module's cards included, is inside glass and gets the wash.
    @Entry var notchOnDesktop = false
}

/// How a card, a field, a chip or the selected tab is drawn, as a value, so a test reads what the view draws. It depends on the
/// surface, on where the card is and on the debug switches, and only on glass: the classic notch always gets the wash it has always had.
nonisolated struct NotchCardPlan: Equatable, Sendable {
    enum Fill: Equatable, Sendable {
        /// `NotchTokens.fill(opacity)` behind the shape: today's wash, on the classic notch and on every card inside glass.
        case wash(Double)
        /// What marks the selection inside glass or on the classic notch: the accent at `NotchTokens.selectionOpacity`, and on glass
        /// also a rim of the label colour (the selected tab's capsule as it is today).
        case selectedWash(rim: Bool)
        /// A glass shape of its own: only straight on the desktop.
        case glass(Glass)
        /// A solid white tile, for the selection with `selected=white`: `notchCard` draws its content in black.
        case onTile
    }

    let fill: Fill

    /// How much of the accent tints a selected chip's glass on the desktop: more than the notch's own hint, since it has to mark a state.
    static let selectedTintOpacity = 0.5

    /// The card for `surface` under `switches`. `fill` is the wash's opacity (a module keeps its own, 0.08 being the usual);
    /// `selected` is a chip or tab that is on; `interactive` is for glass that is a control; `onDesktop` says the card sits straight
    /// on the desktop, which is the only place it is glass (and only with the panel `tiles`).
    static func resolve(
        surface: NotchSurface, switches: NotchGlassSwitches, accent: Color, fill: Double = 0.08, selected: Bool = false,
        interactive: Bool = false, onDesktop: Bool = false
    ) -> NotchCardPlan {
        guard surface.isLiquidGlass else {
            return NotchCardPlan(fill: selected ? .selectedWash(rim: false) : .wash(fill))
        }
        if selected, switches.selected == .white { return NotchCardPlan(fill: .onTile) }
        guard onDesktop, switches.panel == .tiles else {
            return NotchCardPlan(fill: selected ? .selectedWash(rim: true) : .wash(fill))
        }
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
    /// look. Glass is never nested in glass: inside the notch's glass or in a tile the card is the wash, and only a card that
    /// sits straight on the desktop, which is what the debug panel `tiles` makes of the sample strip, is a glass shape of its own,
    /// of the same variant as the notch.
    ///
    /// `selected` marks a chip or tab that is on: the accent wash (with a rim on glass), or with `debug.glass.selected=white` a
    /// solid white tile on which the content is drawn in black, or, on the desktop, glass tinted with the accent. `interactive` is for
    /// a card that is a control, so its glass, when it has one, reacts to the pointer.
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
    @Environment(\.notchOnDesktop) private var onDesktop

    func body(content: Content) -> some View {
        let plan = NotchCardPlan.resolve(
            surface: surface, switches: switches, accent: accent, fill: fill, selected: selected, interactive: interactive,
            onDesktop: onDesktop
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
            content.background(Color.black.opacity(switches.dim), in: shape).glassEffect(glass, in: shape)
        case .onTile:
            content.foregroundStyle(Color.black).background(Color.white, in: shape)
        }
    }
}
