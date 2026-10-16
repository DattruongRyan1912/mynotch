import MyNotchCore
import SwiftUI

/// The size of the tab bar's parts, which the open notch with `tiles` works the capsule behind it out from (`NotchTilesLayout`), so
/// it cannot drift from the tab bar it holds.
nonisolated enum TabBarMetrics {
    /// One tab's icon and the room it takes.
    static let iconSize = CGSize(width: 30, height: 24)
    /// The space between two tabs.
    static let spacing: CGFloat = 6
    /// The badge of the "Khác" item: the circle, and the icon in it.
    static let badgeSize: CGFloat = 11
    static let badgeIconSize: CGFloat = 6.5

    /// The width of a tab bar with `count` tabs.
    static func width(count: Int) -> CGFloat {
        count > 0 ? CGFloat(count) * iconSize.width + CGFloat(count - 1) * spacing : 0
    }
}

struct TabBar: View {
    let tabs: [NotchTab]
    let selected: ModuleID?
    /// A small icon (a system image name) on an item, for the "Khác" item while one of the pages in it is open: which one.
    var badges: [ModuleID: String] = [:]
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

    /// The icon of the page open under an item, small, in the corner of it.
    private func badge(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: TabBarMetrics.badgeIconSize, weight: .bold))
            .foregroundStyle(surface.primaryStyle)
            .frame(width: TabBarMetrics.badgeSize, height: TabBarMetrics.badgeSize)
            .background { Circle().fill(accent) }
            .offset(x: 2, y: 1)
            .accessibilityHidden(true)
    }

    var body: some View {
        HStack(spacing: TabBarMetrics.spacing) {
            ForEach(tabs) { tab in
                Button { onSelect(tab.id) } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: TabBarMetrics.iconSize.width, height: TabBarMetrics.iconSize.height)
                        .foregroundStyle(tab.id == selected ? surface.primaryStyle : surface.secondaryStyle)
                        .background { if tab.id == selected { selection } }
                        .overlay(alignment: .bottomTrailing) { if let badge = badges[tab.id], tab.id == selected { self.badge(badge) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityAddTraits(tab.id == selected ? .isSelected : [])
            }
        }
    }
}
