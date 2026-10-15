import MyNotchCore
import SwiftUI

struct TabBar: View {
    let tabs: [NotchTab]
    let selected: ModuleID?
    let onSelect: (ModuleID) -> Void
    @Environment(\.notchAccent) private var accent
    @Environment(\.notchSurface) private var surface
    @Environment(\.notchGlassSwitches) private var switches

    /// How the selected tab is drawn: the capsule below, or (on glass, with the debug switch `cards=glass`) a card of its own, glass
    /// tinted with the accent or a white tile, on which `notchCard` draws the glyph in black.
    private var drawsSelectionAsCard: Bool {
        let card = NotchCardPlan.resolve(surface: surface, switches: switches, accent: accent, selected: true, interactive: true)
        if case .selectedWash = card.fill { return false }
        return true
    }

    /// The accent behind the selected tab; on glass also a rim of the primary label colour, so that an accent as light as the
    /// glass still marks it.
    private var selection: some View {
        Capsule().fill(accent.opacity(NotchTokens.selectionOpacity))
            .overlay {
                if surface.isLiquidGlass { Capsule().strokeBorder(.primary.opacity(NotchTokens.glassSelectionRim), lineWidth: 1) }
            }
    }

    private func icon(of tab: NotchTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 30, height: 24)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                Button { onSelect(tab.id) } label: {
                    icon(of: tab)
                        .foregroundStyle(tab.id == selected ? surface.primaryStyle : surface.secondaryStyle)
                        .background { if tab.id == selected && !drawsSelectionAsCard { selection } }
                        .selectionCard(tab.id == selected && drawsSelectionAsCard)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityAddTraits(tab.id == selected ? .isSelected : [])
            }
        }
    }
}

private extension View {
    /// The selected tab as a card (see `notchCard`), when the tab bar draws it as one; the view itself, with no extra layer, for
    /// every tab in the usual look.
    @ViewBuilder func selectionCard(_ isCard: Bool) -> some View {
        if isCard { notchCard(in: Capsule(), interactive: true, selected: true) } else { self }
    }
}
