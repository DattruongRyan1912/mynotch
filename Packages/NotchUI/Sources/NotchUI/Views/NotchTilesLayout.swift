import CoreGraphics

/// Where the tab bar's capsule and the content's tile are, for the `tiles` shape of the open notch: a pure value of the
/// notch's geometry, so what the views are given and what a test reads are the same numbers.
///
/// Both tiles are centred on the notch (its centre is the panel's), so a tile is a size and the distance from the top of the panel.
/// When the notch is not open they are where the collapsed notch is: its body, which is inside its shape, so their glass is inside
/// the notch's own glass and the union is the notch's silhouette. When it opens they spring from there (`NotchTokens.spring`) to
/// where the tab page puts them, and on close back; so the glass splits out of the notch and merges into it.
nonisolated struct NotchTilesLayout: Equatable, Sendable {
    /// One tile: its size and the distance of its top from the top of the panel.
    struct Tile: Equatable, Sendable {
        var size: CGSize
        var top: CGFloat
    }

    /// nil with a single tab, which has no capsule.
    var tabBar: Tile?
    var content: Tile

    /// The tiles of the open notch (and of a notch showing a toast over a tab, which keeps them where they are): `shapeSize` is the
    /// notch's size, `notchHeight` the height of the notch's body that the tab page starts under, `topRadius` the radius of the
    /// shape's ears, which the content is inset by (and by `NotchTokens.padding`), and `tabCount` the number of tabs.
    static func open(shapeSize: CGSize, notchHeight: CGFloat, topRadius: CGFloat, tabCount: Int) -> NotchTilesLayout {
        let inset = topRadius + NotchTokens.padding
        let width = shapeSize.width - 2 * inset
        var top = notchHeight
        var bar: Tile?
        if tabCount >= 2 {
            let size = CGSize(
                width: TabBarMetrics.width(count: tabCount) + 2 * NotchGlassPlan.tabBarInset.width,
                height: TabBarMetrics.iconSize.height + 2 * NotchGlassPlan.tabBarInset.height
            )
            bar = Tile(size: size, top: top)
            top += size.height + NotchGlassPlan.tileGap
        }
        let height = max(shapeSize.height - NotchTokens.padding - top, 0)
        return NotchTilesLayout(tabBar: bar, content: Tile(size: CGSize(width: width, height: height), top: top))
    }

    /// The tiles of the notch that is not open: both are the body of the collapsed notch, `collapsedSize` being its size with the ears
    /// (`NotchGeometry.shapeSize` of `closed` or `compact`) and `topRadius` the radius of those ears. `hasTabBar` says whether there is a
    /// capsule to keep there.
    static func rest(collapsedSize: CGSize, topRadius: CGFloat, hasTabBar: Bool) -> NotchTilesLayout {
        let body = Tile(size: CGSize(width: max(collapsedSize.width - 2 * topRadius, 0), height: collapsedSize.height), top: 0)
        return NotchTilesLayout(tabBar: hasTabBar ? body : nil, content: body)
    }
}
