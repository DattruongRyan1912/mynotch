import MyNotchCore
import SwiftUI

/// What the "Khác" item of the tab bar shows: the pages in it as a compact grid, an icon over a title, about four to a row. Choosing one
/// opens that page.
struct MoreTabGrid: View {
    let pages: [NotchTab]
    let open: (ModuleID) -> Void
    @Environment(\.notchSurface) private var surface

    static let columns = 4
    static let cellHeight: CGFloat = 54
    static let spacing: CGFloat = 8

    /// How many rows `count` pages take.
    static func rows(for count: Int) -> Int { (max(count, 0) + columns - 1) / columns }

    /// The height the notch gives the grid of `count` pages: the grid, and under the tab bar what any page has under it (the padding and the
    /// tab bar's band), held to what a tab gets. More than three rows scroll.
    static func contentHeight(pageCount count: Int) -> CGFloat {
        let rows = CGFloat(rows(for: count))
        let grid = rows * cellHeight + max(rows - 1, 0) * spacing
        let chrome = NotchTokens.padding + TabBarMetrics.iconSize.height + NotchTilesLayout.slabTabBarSpacing
        return min(max(grid + chrome, NotchTab.heightRange.lowerBound), NotchTab.heightRange.upperBound)
    }

    var body: some View {
        let grid = LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: Self.columns), spacing: Self.spacing
        ) {
            ForEach(pages) { page in
                Button { open(page.id) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: page.systemImage).font(.system(size: 16, weight: .medium))
                        Text(page.title).font(.system(size: 10.5)).lineLimit(1).truncationMode(.tail)
                    }
                    .foregroundStyle(surface.primaryStyle)
                    .frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight)
                    .padding(.horizontal, 4)
                    .background { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NotchTokens.fill(0.08)) }
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(MoreCellStyle())
                .help(page.title)
                .accessibilityLabel(page.title)
            }
        }
        if Self.rows(for: pages.count) > 3 {
            ScrollView(.vertical) { grid }.scrollIndicators(.hidden)
        } else {
            grid.frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// A cell dims while it is pressed.
private struct MoreCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
