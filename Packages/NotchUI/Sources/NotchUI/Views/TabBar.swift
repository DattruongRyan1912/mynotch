import MyNotchCore
import SwiftUI

struct TabBar: View {
    let tabs: [NotchTab]
    let selected: ModuleID?
    let onSelect: (ModuleID) -> Void
    @Environment(\.notchAccent) private var accent
    @Environment(\.notchSurface) private var surface

    /// The accent behind the selected tab; on glass also a rim of the primary label colour, so that an accent as light as the
    /// glass still marks it.
    private var selection: some View {
        Capsule().fill(accent.opacity(NotchTokens.selectionOpacity))
            .overlay {
                if surface.isLiquidGlass { Capsule().strokeBorder(.primary.opacity(NotchTokens.glassSelectionRim), lineWidth: 1) }
            }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                Button { onSelect(tab.id) } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .foregroundStyle(tab.id == selected ? surface.primaryStyle : surface.secondaryStyle)
                        .background { if tab.id == selected { selection } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityAddTraits(tab.id == selected ? .isSelected : [])
            }
        }
    }
}
