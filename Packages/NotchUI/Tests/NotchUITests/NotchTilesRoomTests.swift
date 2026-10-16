import CoreGraphics
import MyNotchCore
import MyNotchTestSupport
import Observation
import Testing
@testable import NotchUI

/// With tiles the open notch is taller by what the tiles' own chrome takes (the capsule row over the tile, and the tile's inset round
/// the content), so that a tab has the room it has in one piece, and the hit area and the panel follow it.
@Suite struct NotchTilesRoomTests {
    let tilePad = NotchGlassPlan.tilePadding
    let padding = NotchTokens.padding

    func geometry(_ screen: ScreenDescriptor, _ style: VirtualNotchStyle = .notch, tiles: Bool) -> NotchGeometry {
        NotchGeometry(screen: screen, config: NotchLayoutConfig(virtualNotchStyle: style, opensAsTiles: tiles))
    }

    /// Every display and style the notch is drawn for, as (name, screen, style).
    static let displays: [(String, ScreenDescriptor, VirtualNotchStyle)] = [
        ("MacBook", NotchGeometryTests.macBook14, .notch), ("external notch", NotchGeometryTests.external, .notch),
        ("external pill", NotchGeometryTests.external, .pill),
    ]

    // MARK: the chrome

    @Test func theChromeIsTheTilesInsetAndTheCapsuleRowOverWhatTheSlabsTabBarTakes() {
        // One tab: no capsule, only the tile's inset on the top and the bottom. With a capsule: the capsule and its gap over the
        // slab's tab bar and its spacing as well.
        #expect(NotchTilesLayout.extraHeight(tabCount: 1) == 2 * tilePad)
        #expect(NotchTilesLayout.extraHeight(tabCount: 0) == 2 * tilePad)
        let capsule = TabBarMetrics.iconSize.height + 2 * NotchGlassPlan.tabBarInset.height
        let slabBar = TabBarMetrics.iconSize.height + NotchTilesLayout.slabTabBarSpacing
        for tabs in [2, 3, 8] {
            #expect(NotchTilesLayout.extraHeight(tabCount: tabs) == 2 * tilePad + capsule + NotchGlassPlan.tileGap - slabBar)
        }
        // The numbers the user sees: 16 and 24 pt, which tiles used to take from the modules.
        #expect(NotchTilesLayout.extraHeight(tabCount: 1) == 16 && NotchTilesLayout.extraHeight(tabCount: 2) == 24)
    }

    @Test func onlyAnotchMadeOfTilesHasAnyChrome() {
        for (name, screen, style) in Self.displays {
            #expect(geometry(screen, style, tiles: false).tilesChrome(tabCount: 2) == 0, Comment(rawValue: name))
            #expect(geometry(screen, style, tiles: true).tilesChrome(tabCount: 2) == 24, Comment(rawValue: name))
            #expect(geometry(screen, style, tiles: true).tilesChrome(tabCount: 1) == 16, Comment(rawValue: name))
        }
    }

    @Test func theSettingsMakeTheNotchOpenAsTilesOnlyOnLiquidGlassWithTiles() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(NotchLayoutConfig(settings: settings).opensAsTiles == false)
        settings.set(.tiles, for: InterfaceSettings.glassShape)
        #expect(NotchLayoutConfig(settings: settings).opensAsTiles == false, "tiles are for Liquid Glass: the classic look is black")
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        #expect(NotchLayoutConfig(settings: settings).opensAsTiles)
        settings.set(.slab, for: InterfaceSettings.glassShape)
        #expect(NotchLayoutConfig(settings: settings).opensAsTiles == false)
        settings.set(.tiles, for: InterfaceSettings.glassShape)
        settings.set(.clear, for: InterfaceSettings.glassClarity)
        #expect(NotchLayoutConfig(settings: settings).opensAsTiles, "clarity does not matter")
    }

    @Test func aChangeOfTheShapeOrTheLookReachesTheLoopThatRedrawsTheNotches() async {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        final class Seen { var tiles: [Bool] = [] }
        let seen = Seen()
        let loop = Task {
            for await config in Observations({ NotchLayoutConfig(settings: settings) }) { seen.tiles.append(config.opensAsTiles) }
        }
        defer { loop.cancel() }
        func eventually(_ condition: () -> Bool) async -> Bool {
            for _ in 0..<400 {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(5))
            }
            return condition()
        }
        #expect(await eventually { seen.tiles.last == false })
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        settings.set(.tiles, for: InterfaceSettings.glassShape)
        #expect(await eventually { seen.tiles.last == true }, "the notch is rebuilt, and its panel and hit area follow")
        settings.set(.classic, for: InterfaceSettings.look)
        #expect(await eventually { seen.tiles.last == false })
    }

    // MARK: the open notch, its hit area and the panel follow

    @Test func theOpenNotchWithTilesIsTallerByTheChromeAndTheCollapsedOnesAreNot() {
        for (name, screen, style) in Self.displays {
            let slab = geometry(screen, style, tiles: false)
            let tiled = geometry(screen, style, tiles: true)
            for content in stride(from: NotchTab.heightRange.lowerBound, through: NotchGeometry.maxContentHeight, by: 20) {
                for tabs in [1, 2, 4] {
                    for state in [NotchState.open("a"), .open(nil), .toast] {
                        let a = slab.shapeSize(for: state, contentHeight: content, tabCount: tabs)
                        let b = tiled.shapeSize(for: state, contentHeight: content, tabCount: tabs)
                        #expect(b.height - a.height == NotchTilesLayout.extraHeight(tabCount: tabs), "\(name) \(state) \(content) \(tabs)")
                        #expect(a.width == b.width, "the width is the same: the tile reaches further out instead")
                    }
                }
            }
            for state in [NotchState.closed, .compact] {
                #expect(tiled.shapeSize(for: state, bottomHeight: 30, tabCount: 3) == slab.shapeSize(for: state, bottomHeight: 30, tabCount: 3), "\(name) \(state)")
            }
        }
    }

    @Test func aHardwareNotchWithoutTilesIsExactlyAsItWasWhateverTheTabCount() {
        let book = geometry(NotchGeometryTests.macBook14, tiles: false)
        for tabs in [1, 2, 5] {
            #expect(book.shapeSize(for: .open(nil), contentHeight: 190, tabCount: tabs) == CGSize(width: 600, height: 222))
        }
        #expect(book.panelSize == CGSize(width: 900, height: 32 + 240))
        #expect(book.shapeSize(for: .open(nil), contentHeight: 190) == CGSize(width: 600, height: 222), "and with no tab count given")
    }

    @Test func theHitAreaAndTheHoverZoneFollowTheTallerOpenNotch() {
        for (name, screen, style) in Self.displays {
            let slab = geometry(screen, style, tiles: false)
            let tiled = geometry(screen, style, tiles: true)
            let frame = screen.frame
            for tabs in [1, 2] {
                let extra = NotchTilesLayout.extraHeight(tabCount: tabs)
                let a = slab.hitRect(for: .open(nil), contentHeight: 190, tabCount: tabs, in: frame)
                let b = tiled.hitRect(for: .open(nil), contentHeight: 190, tabCount: tabs, in: frame)
                #expect(b.height - a.height == extra && b.minY == a.minY - extra, "\(name) \(tabs): grows down, its top stays")
                let d = tiled.dragHitRect(for: .open(nil), contentHeight: 190, tabCount: tabs, in: frame)
                #expect(d.height - slab.dragHitRect(for: .open(nil), contentHeight: 190, tabCount: tabs, in: frame).height == extra)
                // A point under where the slab ends (and its 8 pt of hit padding) is inside the tiles' notch, and outside the slab's.
                let underSlab = CGPoint(
                    x: frame.midX + slab.centerOffset, y: frame.maxY - slab.topGap - slab.shapeSize(for: .open(nil), contentHeight: 190).height - 12
                )
                #expect(slab.pointerZone(at: underSlab, state: .open(nil), contentHeight: 190, tabCount: tabs, in: frame) == .outside, "\(name) \(tabs)")
                #expect(tiled.pointerZone(at: underSlab, state: .open(nil), contentHeight: 190, tabCount: tabs, in: frame) == .notch, "\(name) \(tabs)")
                #expect(tiled.pointerZone(at: underSlab, state: .open(nil), contentHeight: 190, dragging: true, tabCount: tabs, in: frame) == .notch)
                // And just under the tiles' own bottom (and the padding) is outside again.
                let underTiles = CGPoint(x: underSlab.x, y: underSlab.y - extra - 12)
                #expect(tiled.pointerZone(at: underTiles, state: .open(nil), contentHeight: 190, tabCount: tabs, in: frame) == .outside, "\(name) \(tabs)")
            }
        }
    }

    @Test func theFixedPanelHoldsTheTallestOpenNotchWithTilesAndIsTheSameWithout() {
        for (name, screen, style) in Self.displays {
            let slab = geometry(screen, style, tiles: false)
            let tiled = geometry(screen, style, tiles: true)
            #expect(tiled.panelSize.width == slab.panelSize.width)
            #expect(tiled.panelSize.height >= slab.panelSize.height, Comment(rawValue: name))
            let panel = tiled.panelFrame(in: screen.frame)
            for tabs in [1, 2, 3] {
                for state in [NotchState.open(nil), .toast] {
                    let size = tiled.shapeSize(for: state, contentHeight: NotchGeometry.maxContentHeight, tabCount: tabs)
                    let rect = CGRect(x: panel.midX - size.width / 2, y: panel.maxY - tiled.topGap - size.height, width: size.width, height: size.height)
                    #expect(panel.contains(rect), "\(name) \(tabs) \(state)")
                }
            }
        }
        // The panel of the notch that does not have tiles is the one it had.
        #expect(geometry(NotchGeometryTests.macBook14, tiles: false).panelSize.height == CGFloat(32 + 240))
        #expect(geometry(NotchGeometryTests.external, tiles: false).panelSize.height == CGFloat(25 + 240))
        #expect(geometry(NotchGeometryTests.macBook14, tiles: true).panelSize.height == CGFloat(32 + 240 + 24))
    }

    // MARK: the room of a tab

    /// What a tab gets in one piece: the width between the content's insets and the height under the tab bar (if any) and over the padding.
    func slabRoom(_ geometry: NotchGeometry, content: CGFloat, tabs: Int) -> CGSize {
        let size = geometry.shapeSize(for: .open(nil), contentHeight: content)
        let ear = geometry.cornerRadii(for: .open(nil)).top
        let bar = tabs >= 2 ? TabBarMetrics.iconSize.height + NotchTilesLayout.slabTabBarSpacing : 0
        return CGSize(width: size.width - 2 * (ear + padding), height: size.height - geometry.openTopInset - padding - bar)
    }

    @Test func theContentAreaInTilesIsExactlyTheSlabsForEveryDisplayHeightAndNumberOfTabs() {
        for (name, screen, style) in Self.displays {
            let slab = geometry(screen, style, tiles: false)
            let tiled = geometry(screen, style, tiles: true)
            for content in stride(from: NotchTab.heightRange.lowerBound, through: NotchGeometry.maxContentHeight, by: 10) {
                for tabs in [1, 2, 3, 8] {
                    let layout = NotchTilesLayout.open(
                        shapeSize: tiled.shapeSize(for: .open(nil), contentHeight: content, tabCount: tabs), topInset: tiled.openTopInset,
                        topRadius: tiled.cornerRadii(for: .open(nil)).top, tabCount: tabs
                    )
                    let inner = CGSize(width: layout.content.size.width - 2 * tilePad, height: layout.content.size.height - 2 * tilePad)
                    let room = slabRoom(slab, content: content, tabs: tabs)
                    #expect(inner == room, "\(name) asks \(content), \(tabs) tabs: \(inner) against \(room)")
                }
            }
        }
    }

    @Test func theTileHoldsTheContentWithItsInsetOnEverySideAndTheCornersAreConcentric() {
        for (name, screen, style) in Self.displays {
            let tiled = geometry(screen, style, tiles: true)
            for tabs in [1, 2] {
                let shape = tiled.shapeSize(for: .open(nil), contentHeight: 190, tabCount: tabs)
                let layout = NotchTilesLayout.open(
                    shapeSize: shape, topInset: tiled.openTopInset, topRadius: tiled.cornerRadii(for: .open(nil)).top, tabCount: tabs
                )
                let tile = CGRect(x: (shape.width - layout.content.size.width) / 2, y: layout.content.top, width: layout.content.size.width, height: layout.content.size.height)
                // The content, as the root view lays it out: the tile's size less the inset all round, from the inset down.
                let content = CGRect(x: tile.minX + tilePad, y: tile.minY + tilePad, width: tile.width - 2 * tilePad, height: tile.height - 2 * tilePad)
                #expect(tile.insetBy(dx: tilePad, dy: tilePad) == content, "\(name) \(tabs): the tile contains the content and its inset")
                #expect(content.minX - tile.minX == tilePad && tile.maxX - content.maxX == tilePad && tile.maxY - content.maxY == tilePad)
                // The tile's radius is the open notch's less the padding, and the content's corners (inset by `tilePad`) keep a radius
                // of what is left, never below 0, so nothing meets the tile's edge.
                let radius = NotchGlassPlan.concentricRadius(outer: tiled.cornerRadii(for: .open(nil)).bottom, inset: padding)
                #expect(radius == 10 && radius - tilePad >= 0)
                // The tile is inside the notch's rect with the padding at the bottom.
                #expect(CGRect(origin: .zero, size: shape).contains(tile))
                #expect(shape.height - tile.maxY == padding)
            }
        }
    }

    @Test func theCapsuleAndTheTileDoNotOverlapAndTheGapIsBetweenThem() {
        let tiled = geometry(NotchGeometryTests.macBook14, tiles: true)
        let layout = NotchTilesLayout.open(
            shapeSize: tiled.shapeSize(for: .open(nil), contentHeight: 190, tabCount: 3), topInset: tiled.openTopInset,
            topRadius: tiled.cornerRadii(for: .open(nil)).top, tabCount: 3
        )
        let bar = layout.tabBar!
        #expect(bar.top + bar.size.height + NotchGlassPlan.tileGap == layout.content.top)
    }
}
