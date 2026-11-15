import CoreGraphics
import MyNotchCore
import Testing
@testable import NotchUI

/// With Liquid Glass tiles on a pill, the tab bar's capsule takes the collapsed pill's place (the same top under the gap, the same height,
/// the same centre) and the content's tile comes out under it, keeping the room it has in one piece.
@Suite struct NotchPillBarTests {
    let external = NotchGeometryTests.external
    let gap = NotchGeometry.pillTopGap

    func geometry(_ height: CGFloat, tiles: Bool = true, width: CGFloat = 185) -> NotchGeometry {
        NotchGeometry(
            screen: external, config: NotchLayoutConfig(virtualNotchWidth: width, virtualNotchStyle: .pill, opensAsTiles: tiles, pillHeight: height)
        )
    }

    func open(_ geometry: NotchGeometry, tabs: Int, content: CGFloat = 190) -> NotchTilesLayout {
        NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: content, tabCount: tabs), topInset: geometry.openTopInset,
            topRadius: geometry.cornerRadii(for: .open(nil)).top, tabCount: tabs, bar: geometry.tabBarCapsule(tabCount: tabs)
        )
    }

    func rest(_ geometry: NotchGeometry) -> NotchTilesLayout {
        NotchTilesLayout.rest(
            collapsedSize: geometry.shapeSize(for: .closed), topRadius: geometry.cornerRadii(for: .closed).top, hasTabBar: true
        )
    }

    /// A tile as the rect it covers on the screen, centred on the notch and `gap` under the top edge.
    func onScreen(_ tile: NotchTilesLayout.Tile, _ geometry: NotchGeometry) -> CGRect {
        let frame = external.frame
        return CGRect(
            x: frame.midX + geometry.centerOffset - tile.size.width / 2, y: frame.maxY - geometry.topGap - tile.top - tile.size.height,
            width: tile.size.width, height: tile.size.height
        )
    }

    static let heights: [CGFloat] = [24, 28, 32, 40, 56]

    // MARK: the capsule is the pill

    @Test func theCapsuleIsInThePillsPlaceSameTopSameHeightSameCentre() {
        for height in Self.heights {
            for tabs in [2, 3, 12] {
                let geometry = geometry(height)
                let pillRect = onScreen(rest(geometry).tabBar!, geometry)
                let capsule = onScreen(open(geometry, tabs: tabs).tabBar!, geometry)
                let name = "pill \(height), \(tabs) tabs"
                #expect(pillRect == CGRect(x: external.frame.midX - 92.5, y: external.frame.maxY - gap - height, width: 185, height: height), Comment(rawValue: name))
                #expect(capsule.maxY == pillRect.maxY, "\(name): the same top, under the same gap")
                #expect(capsule.minY == pillRect.minY && capsule.height == pillRect.height, "\(name): the same height")
                #expect(capsule.height == height, Comment(rawValue: name))
                #expect(capsule.midX == pillRect.midX, "\(name): the same centre")
                #expect(external.frame.maxY - capsule.maxY == gap, "\(name): the gap above it is the pill's")
            }
        }
    }

    @Test func theCapsuleIsAsWideAsTheTabBarNeedsSoTheTabBarsWidthDecidesWhetherThePillWidensOrNarrows() {
        let geometry = geometry(32)
        for tabs in [2, 3, 5, 12] {
            let capsule = open(geometry, tabs: tabs).tabBar!
            #expect(capsule.size.width == TabBarMetrics.width(count: tabs) + 2 * NotchGlassPlan.tabBarInset.width, "\(tabs) tabs")
        }
        #expect(open(geometry, tabs: 12).tabBar!.size.width > rest(geometry).tabBar!.size.width, "twelve tabs are wider than the pill: it widens sideways")
        #expect(open(geometry, tabs: 3).tabBar!.size.width < rest(geometry).tabBar!.size.width, "a few are narrower")
        // Only the width travels between the pill and the capsule, which is how the pill widens into the bar.
        let from = rest(geometry).tabBar!, to = open(geometry, tabs: 12).tabBar!
        #expect(from.top == to.top && from.size.height == to.size.height)
    }

    @Test func theTabsIconsAreCentredInTheCapsuleWhateverItsHeight() {
        for height in Self.heights {
            let bar = geometry(height).tabBarCapsule(tabCount: 3)!
            let inset = (bar.height - TabBarMetrics.iconSize.height) / 2
            #expect(inset + TabBarMetrics.iconSize.height + inset == bar.height, "\(height)")
            // (At the shortest pill the icons fill the capsule's height.)
            #expect(inset >= 0, "\(height)")
        }
    }

    // MARK: the tile

    @Test func theTileIsUnderTheCapsuleWithTheUsualGap() {
        for height in Self.heights {
            let geometry = geometry(height)
            for tabs in [2, 4] {
                let layout = open(geometry, tabs: tabs)
                let capsule = layout.tabBar!
                #expect(layout.content.top == capsule.top + capsule.size.height + NotchGlassPlan.tileGap, "\(height) \(tabs)")
                #expect(layout.content.top == height + NotchGlassPlan.tileGap, "under the pill's height and the gap")
                #expect(onScreen(layout.content, geometry).maxY == onScreen(capsule, geometry).minY - NotchGlassPlan.tileGap)
            }
        }
    }

    @Test func theTileKeepsTheRoomOneGivesItAtEveryPillHeight() {
        for height in Self.heights {
            let tiled = geometry(height)
            let slab = geometry(height, tiles: false)
            for tabs in [2, 3, 12] {
                for content in [CGFloat(120), 190, 240] {
                    let layout = open(tiled, tabs: tabs, content: content)
                    let inner = CGSize(width: layout.content.size.width - 2 * NotchGlassPlan.tilePadding, height: layout.content.size.height - 2 * NotchGlassPlan.tilePadding)
                    let size = slab.shapeSize(for: .open(nil), contentHeight: content)
                    let room = CGSize(width: size.width - 2 * NotchTokens.padding, height: size.height - slab.openTopInset - NotchTokens.padding - 30)
                    #expect(inner == room, "pill \(height), \(tabs) tabs, asks \(content): \(inner) against \(room)")
                }
            }
        }
    }

    @Test func theNotchIsTallerByThePillsHeightLessTwentyAndThePanelHoldsIt() {
        for height in Self.heights {
            let tiled = geometry(height), slab = geometry(height, tiles: false)
            #expect(tiled.tilesChrome(tabCount: 2) == height - 20, "\(height)")
            #expect(tiled.shapeSize(for: .open(nil), contentHeight: 190, tabCount: 2).height - slab.shapeSize(for: .open(nil), contentHeight: 190).height == height - 20)
            #expect(tiled.tilesChrome(tabCount: 1) == 16, "one tab has no capsule: only the tile's inset")
            let panel = tiled.panelFrame(in: external.frame)
            for tabs in [1, 2, 3] {
                let size = tiled.shapeSize(for: .open(nil), contentHeight: 240, tabCount: tabs)
                let rect = CGRect(x: panel.midX - size.width / 2, y: panel.maxY - gap - size.height, width: size.width, height: size.height)
                #expect(panel.contains(rect), "\(height) \(tabs)")
            }
        }
    }

    // MARK: everything else is as it was

    @Test func aSingleTabHasNoCapsuleAndItsTileIsWhereItWas() {
        let tiled = geometry(40)
        #expect(tiled.tabBarCapsule(tabCount: 1) == nil && tiled.tabBarCapsule(tabCount: 0) == nil)
        let layout = open(tiled, tabs: 1)
        #expect(layout.tabBar == nil)
        #expect(layout.content.top == tiled.openTopInset)
    }

    @Test func theSlabOfAPillHasNoChromeAndStartsAtThePillsTop() {
        for height in Self.heights {
            let slab = geometry(height, tiles: false)
            #expect(slab.tilesChrome(tabCount: 2) == 0 && slab.tilesChrome(tabCount: 1) == 0)
            #expect(slab.shapeSize(for: .open(nil), contentHeight: 190) == CGSize(width: 600, height: 14 + 190), "the open rounded rectangle")
            // It starts at the pill's top: under the same gap.
            #expect(slab.hitRect(for: .open(nil), contentHeight: 190, in: external.frame).maxY == external.frame.maxY + 1)
            #expect(slab.topGap == gap)
        }
    }

    @Test func aNotchAndAHardwareNotchKeepTheirCapsuleUnderTheTopInset() {
        for (screen, style) in [(NotchGeometryTests.external, VirtualNotchStyle.notch), (NotchGeometryTests.macBook14, .pill), (NotchGeometryTests.macBook14, .notch)] {
            let geometry = NotchGeometry(screen: screen, config: NotchLayoutConfig(virtualNotchStyle: style, opensAsTiles: true, pillHeight: 56))
            let bar = geometry.tabBarCapsule(tabCount: 2)
            #expect(bar == NotchTilesLayout.Bar(top: geometry.openTopInset, height: 30), "\(style) on \(screen.safeAreaTop)")
            #expect(geometry.tilesChrome(tabCount: 2) == 24, "as it was")
            #expect(geometry.tilesChrome(tabCount: 1) == 16)
            let layout = NotchTilesLayout.open(
                shapeSize: geometry.shapeSize(for: .open(nil), tabCount: 2), topInset: geometry.openTopInset,
                topRadius: geometry.cornerRadii(for: .open(nil)).top, tabCount: 2, bar: bar
            )
            let plain = NotchTilesLayout.open(
                shapeSize: geometry.shapeSize(for: .open(nil), tabCount: 2), topInset: geometry.openTopInset,
                topRadius: geometry.cornerRadii(for: .open(nil)).top, tabCount: 2
            )
            #expect(layout == plain, "a bar placement of the default is the default")
        }
    }
}
