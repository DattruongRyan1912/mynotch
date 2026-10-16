import CoreGraphics

/// Where the tab bar's capsule and the content's tile are, for the `tiles` shape of the open notch: a pure value of the notch's
/// geometry, so what the views are given and what a test reads are the same numbers.
///
/// Both tiles are centred on the notch (its centre is the panel's), so a tile is a size and the distance from the top of the panel.
/// When the notch is not open they are where the collapsed notch is: its body, which is inside its shape. When it opens they spring from
/// there (`NotchTokens.spring`) to where the tab page puts them, and on close back; so the glass splits out of the notch and merges into
/// it. Closing, their glass is dropped on the way (`NotchTilesLayout.wantsGlass`) and the notch's own view is above them (see
/// `NotchRootView`), so at rest there is none, and while it fades none of it is above the strip.
nonisolated struct NotchTilesLayout: Equatable, Sendable {
    /// One tile: its size and the distance of its top from the top of the panel.
    struct Tile: Equatable, Sendable {
        var size: CGSize
        var top: CGFloat
    }

    /// How far a tile of `size` is from the `rest` size to the `final` one, 0 at rest and 1 where it is open (beyond 1 while the spring
    /// overshoots), in whichever of the two dimensions has the most to travel.
    static func progress(of size: CGSize, from rest: CGSize, to final: CGSize) -> CGFloat {
        let width = abs(final.width - rest.width) >= 1 ? (size.width - rest.width) / (final.width - rest.width) : 0
        let height = abs(final.height - rest.height) >= 1 ? (size.height - rest.height) / (final.height - rest.height) : 0
        return max(width, height)
    }

    /// How far back a closing tile may be, as a part of the way, and still be glass: past it the glass is `Glass.identity`, which the
    /// window server takes about 0.6 s to fade out whatever it is told, so it must start early to be gone soon after the notch has
    /// collapsed. What is left fades under the notch's own view, which is drawn after the tiles, so it is never above the strip's text.
    static let glassUntil: CGFloat = 0.6

    /// What a tile is doing, which decides whether it is glass.
    enum Phase: Sendable {
        /// The notch is open: glass, from the first frame.
        case open
        /// A toast covers the tab, which keeps its tile where it was: not glass, so nothing but the toast's slab is drawn.
        case covered
        /// The notch has closed and the tile is on its way back: glass while it is far from the notch, and never again once it has not
        /// been (a tile that was covered stays glass-less).
        case closing
    }

    /// Whether a tile of `size` is glass in `phase`.
    static func wantsGlass(size: CGSize, rest: CGSize, final: CGSize, phase: Phase) -> Bool {
        switch phase {
        case .open: true
        case .covered: false
        case .closing: progress(of: size, from: rest, to: final) > glassUntil
        }
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
