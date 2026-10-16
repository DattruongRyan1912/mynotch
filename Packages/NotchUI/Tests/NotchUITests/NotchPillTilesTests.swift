import CoreGraphics
import SwiftUI
import Testing
@testable import NotchUI

/// The tiles of Liquid Glass on a pill: they start as the pill and spring out of it into the open rounded rectangle, and on its
/// concentric corners they stay inside its outline all the way.
@Suite struct NotchPillTilesTests {
    let pill = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))
    let notch = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())

    func rest(_ geometry: NotchGeometry, _ state: NotchState) -> NotchTilesLayout {
        NotchTilesLayout.rest(
            collapsedSize: geometry.shapeSize(for: state), topRadius: geometry.cornerRadii(for: state).top, hasTabBar: true
        )
    }

    func open(_ geometry: NotchGeometry, tabs: Int = 3, contentHeight: CGFloat = 190) -> NotchTilesLayout {
        NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: contentHeight), topInset: geometry.openTopInset,
            topRadius: geometry.cornerRadii(for: .open(nil)).top, tabCount: tabs
        )
    }

    @Test func theTilesStartAsTheWholePillWithNoEarsToLeaveOut() {
        for state in [NotchState.closed, .compact] {
            let layout = rest(pill, state)
            let size = pill.shapeSize(for: state)
            #expect(layout.content.size == size, "\(state): the pill's own rect")
            #expect(layout.tabBar?.size == size)
            #expect(layout.content.top == 0 && layout.tabBar?.top == 0, "the gap is the whole notch's, not the tile's")
            // The notch's tiles start inside its ears, which a pill has none of.
            #expect(rest(notch, state).content.size.width == notch.shapeSize(for: state).width - 2 * 6)
        }
    }

    @Test func theOpenTilesAreCentredAndInsetByThePaddingAlone() {
        let size = pill.shapeSize(for: .open(nil), contentHeight: 190)
        let layout = open(pill)
        let tile = layout.content
        #expect(tile.size.width == size.width - 2 * NotchTokens.padding, "no ears: only the padding insets it sideways")
        #expect(NotchTokens.padding + tile.size.width + NotchTokens.padding == size.width, "centred")
        #expect(tile.top + tile.size.height + NotchTokens.padding == size.height, "the padding below it")
        let bar = layout.tabBar
        #expect(bar?.top == NotchTokens.padding, "the capsule is the padding under the top: there is no cutout to keep free")
        #expect((bar?.top ?? 0) + (bar?.size.height ?? 0) + NotchGlassPlan.tileGap == tile.top)
        // The notch's tile is 16 pt narrower: its ears.
        #expect(open(notch).content.size.width == tile.size.width - 16)
    }

    @Test func theOpenContentTileIsConcentricWithTheOpenPillsCorners() {
        let radius = NotchGlassPlan.concentricRadius(outer: pill.cornerRadii(for: .open(nil)).bottom, inset: NotchTokens.padding)
        #expect(radius == 10, "24 less the 14 pt padding")
        let size = pill.shapeSize(for: .open(nil), contentHeight: 190)
        let tile = open(pill).content
        // The tile's bottom corners and the pill's have the same centre.
        let outerCentre = CGPoint(x: pill.cornerRadii(for: .open(nil)).bottom, y: size.height - pill.cornerRadii(for: .open(nil)).bottom)
        let tileCentre = CGPoint(x: NotchTokens.padding + radius, y: tile.top + tile.size.height - radius)
        #expect(outerCentre == tileCentre)
    }

    /// Points along the four edges of `rect`, a point in from each.
    func edge(of rect: CGRect) -> [CGPoint] {
        let steps = stride(from: CGFloat(0), through: 1, by: 0.01)
        return steps.flatMap { t -> [CGPoint] in
            let x = rect.minX + 1 + (rect.width - 2) * t, y = rect.minY + 1 + (rect.height - 2) * t
            return [
                CGPoint(x: x, y: rect.minY + 1), CGPoint(x: x, y: rect.maxY - 1),
                CGPoint(x: rect.minX + 1, y: y), CGPoint(x: rect.maxX - 1, y: y),
            ]
        }
    }

    @Test func theOpenTilesAreInsideThePillsOutlineAndTheStartingPillIsInsideItsTop() throws {
        let size = pill.shapeSize(for: .open(nil), contentHeight: 190)
        let outline = pill.shape(for: .open(nil)).path(in: CGRect(origin: .zero, size: size))
        let layout = open(pill)
        let tileRadius = NotchGlassPlan.concentricRadius(outer: NotchGeometry.pillOpenRadius, inset: NotchTokens.padding)
        let tile = CGRect(x: NotchTokens.padding, y: layout.content.top, width: layout.content.size.width, height: layout.content.size.height)
        let tilePath = RoundedRectangle(cornerRadius: tileRadius, style: .circular).path(in: tile)
        let tileEdge = edge(of: tile).filter { tilePath.contains($0) }
        #expect(tileEdge.count > 100, "the tile's edge is there to check")
        #expect(tileEdge.allSatisfy { outline.contains($0) }, "the tile never sticks out of the open pill")
        // The capsule too.
        let bar = try #require(layout.tabBar)
        let capsule = CGRect(x: (size.width - bar.size.width) / 2, y: bar.top, width: bar.size.width, height: bar.size.height)
        let capsulePath = Capsule().path(in: capsule)
        #expect(edge(of: capsule).filter { capsulePath.contains($0) }.allSatisfy { outline.contains($0) })
        // And the pill it all springs out of is inside the top of the open outline: the tiles start there.
        let body = rest(pill, .closed).content
        let start = CGRect(x: (size.width - body.size.width) / 2, y: 0, width: body.size.width, height: body.size.height)
        let startPath = Capsule().path(in: start)
        #expect(edge(of: start).filter { startPath.contains($0) }.allSatisfy { outline.contains($0) })
    }

    @Test func theContentTileLeavesAndReturnsWithTheRadiusOfTheBodyItIsIn() {
        // A pill's body is a capsule, and the tile starts as one; a notch's body has 10 pt corners, which is the tile's own radius when it
        // is open, so for the notch nothing is different from before the pill.
        #expect(pill.cornerRadii(for: .closed).bottom == pill.notchSize.height / 2)
        #expect(notch.cornerRadii(for: .closed).bottom == 10)
        #expect(notch.cornerRadii(for: .closed).bottom == NotchGlassPlan.concentricRadius(outer: notch.cornerRadii(for: .open(nil)).bottom, inset: NotchTokens.padding))
    }

    @Test func aTileIsBackInThePillWhenItReachesThePillsOwnSize() {
        let rest = rest(pill, .closed)
        let open = open(pill)
        #expect(NotchTilesLayout.isBack(size: rest.content.size, rest: rest.content.size, final: open.content.size))
        #expect(!NotchTilesLayout.isBack(size: open.content.size, rest: rest.content.size, final: open.content.size))
    }
}
