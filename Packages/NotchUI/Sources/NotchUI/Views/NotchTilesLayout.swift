import CoreGraphics

/// Where the tab bar's capsule and the content's tile are, for the `tiles` shape of the open notch: a pure value of the notch's
/// geometry, so what the views are given and what a test reads are the same numbers.
///
/// Both tiles are centred on the notch (its centre is the panel's), so a tile is a size and the distance from the top of the panel.
/// When the notch is not open they are where the collapsed notch is: its body, which is inside its shape. When it opens they spring from
/// there (`NotchTokens.spring`) to where the tab page puts them, and on close back; so the glass splits out of the notch and merges into
/// it. They are glass the whole way, in the same container as the notch's own glass, which is there from the first frame of the close,
/// and they are taken out of the tree when they are back (`NotchTilesLayout.isBack`), so at rest there is none.
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

    /// How far from `rest` a tile may still be, as a part of the way to `final`, and count as back in the notch's body.
    static let backWithin: CGFloat = 0.02

    /// What a tile is doing.
    enum Phase: Sendable {
        /// The notch is open.
        case open
        /// A toast covers the tab, which keeps its tile where it was: not glass, so nothing but the toast's slab is drawn.
        case covered
        /// The notch has closed and the tile is on its way back into its body.
        case closing
    }

    /// Whether a tile of `size` is back in the notch's body (or past it, while the spring overshoots).
    static func isBack(size: CGSize, rest: CGSize, final: CGSize) -> Bool {
        progress(of: size, from: rest, to: final) <= backWithin + 1e-9
    }

    /// The space the slab leaves between its tab bar and the content (`NotchRootView.tabPage`).
    static let slabTabBarSpacing: CGFloat = 6

    /// How much taller the open notch is made of tiles than in one piece, for a tab to have the same room in both: the tile's own inset
    /// all round the content (two `tilePadding`), and with a capsule, the capsule and the gap under it over the tab bar and its spacing
    /// in the slab.
    static func extraHeight(tabCount: Int) -> CGFloat {
        var extra = 2 * NotchGlassPlan.tilePadding
        if tabCount >= 2 {
            let capsule = TabBarMetrics.iconSize.height + 2 * NotchGlassPlan.tabBarInset.height
            extra += capsule + NotchGlassPlan.tileGap - (TabBarMetrics.iconSize.height + slabTabBarSpacing)
        }
        return extra
    }

    /// nil with a single tab, which has no capsule.
    var tabBar: Tile?
    var content: Tile

    /// The tiles of the open notch (and of a notch showing a toast over a tab, which keeps them where they are): `shapeSize` is the
    /// notch's size, `topInset` how far below its top the tab page starts (`NotchGeometry.openTopInset`: under a hardware notch's cutout, or
    /// the padding below the top of a display without one), `topRadius` the radius of the
    /// shape's ears, which the content is inset by (and by `NotchTokens.padding`), and `tabCount` the number of tabs. What a tab shows is
    /// `NotchGlassPlan.tilePadding` inside its tile, so the tile reaches that much further out than the content does in one piece, and
    /// `shapeSize` (which is taller by `extraHeight`) leaves the content the room it has there.
    static func open(shapeSize: CGSize, topInset: CGFloat, topRadius: CGFloat, tabCount: Int) -> NotchTilesLayout {
        let inset = topRadius + NotchTokens.padding - NotchGlassPlan.tilePadding
        let width = shapeSize.width - 2 * inset
        var top = topInset
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
