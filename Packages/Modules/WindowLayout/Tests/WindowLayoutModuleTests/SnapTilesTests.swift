import CoreGraphics
import Testing
@testable import WindowLayoutModule

/// The row of tiles in the open notch and which zone of which tile the pointer is over. The row is drawn from the same
/// frames, so what is highlighted is what a drop would use.
@Suite struct SnapTilesTests {
    /// The content area of a 14" MacBook's open notch: where the row goes (see `NotchGeometry.contentFrame`).
    let content = CGRect(x: 476.5, y: 862, width: 556, height: SnapTiles.height)
    let all = SnapLayout.allCases

    @Test func sixTilesShareTheWidthWithEightPointsBetweenThem() {
        let frames = SnapTiles.frames(count: 6, in: content)
        #expect(frames.count == 6)
        #expect(frames.allSatisfy { $0.width == 86 && $0.height == SnapTiles.height && $0.minY == 862 })
        #expect(frames.map(\.minX) == (0..<6).map { 476.5 + CGFloat($0) * 94 })
        // They fill the area, edge to edge.
        #expect(frames.first?.minX == content.minX && frames.last?.maxX == content.maxX)
    }

    @Test func fewTilesStayAReasonableSizeAndAreCentred() {
        let two = SnapTiles.frames(count: 2, in: content)
        #expect(two.allSatisfy { $0.width == SnapTiles.maxWidth })
        #expect(two[0].minX == content.midX - SnapTiles.maxWidth - SnapTiles.spacing / 2)
        #expect(two[1].maxX == content.midX + SnapTiles.maxWidth + SnapTiles.spacing / 2)
        let one = SnapTiles.frames(count: 1, in: content)
        #expect(one == [CGRect(x: content.midX - SnapTiles.maxWidth / 2, y: 862, width: SnapTiles.maxWidth, height: SnapTiles.height)])
    }

    @Test func noLayoutsMeansNoTiles() {
        #expect(SnapTiles.frames(count: 0, in: content).isEmpty)
        #expect(SnapTiles.target(at: CGPoint(x: content.midX, y: content.midY), layouts: [], content: content) == nil)
    }

    @Test func theGlyphIsAScreenShapedPictureAtTheTopOfTheTile() {
        let tile = SnapTiles.frames(count: 6, in: content)[0]
        let glyph = SnapTiles.glyphFrame(in: tile)
        #expect(glyph.minX == tile.minX + SnapTiles.glyphInset && glyph.maxX == tile.maxX - SnapTiles.glyphInset)
        #expect(glyph.maxY == tile.maxY - SnapTiles.glyphInset)
        #expect(glyph.width / glyph.height == SnapTiles.glyphAspect)
        // The title has the rest of the tile.
        #expect(glyph.minY > tile.minY + 14)
    }

    // MARK: which tile

    @Test func eachTileIsHitOverItsWholeFrameIncludingItsTitle() {
        let frames = SnapTiles.frames(count: 6, in: content)
        for (index, frame) in frames.enumerated() {
            for point in [CGPoint(x: frame.minX + 1, y: frame.minY + 1), CGPoint(x: frame.midX, y: frame.midY), CGPoint(x: frame.maxX - 1, y: frame.maxY - 1)] {
                #expect(SnapTiles.target(at: point, layouts: all, content: content)?.layout == all[index], "tile \(index) at \(point)")
            }
        }
    }

    @Test func theSpaceBetweenTilesAndOutsideTheRowIsNoTile() {
        let frames = SnapTiles.frames(count: 6, in: content)
        for (index, frame) in frames.dropLast().enumerated() {
            let gap = CGPoint(x: frame.maxX + SnapTiles.spacing / 2, y: frame.midY)
            #expect(SnapTiles.target(at: gap, layouts: all, content: content) == nil, "gap after tile \(index)")
        }
        #expect(SnapTiles.target(at: CGPoint(x: content.minX - 1, y: content.midY), layouts: all, content: content) == nil)
        #expect(SnapTiles.target(at: CGPoint(x: content.maxX + 1, y: content.midY), layouts: all, content: content) == nil)
        #expect(SnapTiles.target(at: CGPoint(x: content.midX, y: content.maxY + 1), layouts: all, content: content) == nil)
        #expect(SnapTiles.target(at: CGPoint(x: content.midX, y: content.minY - 1), layouts: all, content: content) == nil)
    }

    @Test func aSubsetOfLayoutsGivesATileOnlyToThoseInOrder() {
        let layouts: [SnapLayout] = [.rightHalf, .thirds]
        let frames = SnapTiles.frames(count: 2, in: content)
        #expect(SnapTiles.target(at: CGPoint(x: frames[0].midX, y: frames[0].midY), layouts: layouts, content: content)?.layout == .rightHalf)
        #expect(SnapTiles.target(at: CGPoint(x: frames[1].midX, y: frames[1].midY), layouts: layouts, content: content)?.layout == .thirds)
    }

    // MARK: which zone

    func point(in tile: CGRect, x fraction: CGFloat, y down: CGFloat) -> CGPoint {
        let glyph = SnapTiles.glyphFrame(in: tile)
        return CGPoint(x: glyph.minX + fraction * glyph.width, y: glyph.maxY - down * glyph.height)
    }

    @Test func aTileWithOneZoneAlwaysMeansThatZone() {
        let frames = SnapTiles.frames(count: 6, in: content)
        for (index, layout) in all.enumerated() where layout.zones.count == 1 {
            let corners = [(0.0, 0.0), (1.0, 1.0), (0.05, 0.95)].map { point(in: frames[index], x: $0.0, y: $0.1) }
            for corner in corners {
                #expect(SnapTiles.target(at: corner, layouts: all, content: content) == SnapTarget(layout: layout, zone: 0))
            }
        }
    }

    @Test func theQuartersTileHasFourZonesByQuadrant() throws {
        let tile = SnapTiles.frames(count: 6, in: content)[3]
        #expect(tile.width > 0)
        let quadrants = [(0.25, 0.25, 0), (0.75, 0.25, 1), (0.25, 0.75, 2), (0.75, 0.75, 3)]
        for (x, y, zone) in quadrants {
            #expect(SnapTiles.target(at: point(in: tile, x: x, y: y), layouts: all, content: content) == SnapTarget(layout: .quarters, zone: zone))
        }
    }

    @Test func theThirdsTileHasThreeZonesByColumn() {
        let tile = SnapTiles.frames(count: 6, in: content)[4]
        for (x, zone) in [(0.1, 0), (0.5, 1), (0.9, 2)] {
            #expect(SnapTiles.target(at: point(in: tile, x: x, y: 0.5), layouts: all, content: content) == SnapTarget(layout: .thirds, zone: zone))
        }
    }

    @Test func overTheTitleOfAMultiZoneTileTheNearestRowOfZonesCounts() {
        let tile = SnapTiles.frames(count: 6, in: content)[3]
        // Below the picture: the bottom zones, by column.
        let belowLeft = CGPoint(x: tile.minX + 10, y: tile.minY + 3)
        let belowRight = CGPoint(x: tile.maxX - 10, y: tile.minY + 3)
        #expect(SnapTiles.target(at: belowLeft, layouts: all, content: content) == SnapTarget(layout: .quarters, zone: 2))
        #expect(SnapTiles.target(at: belowRight, layouts: all, content: content) == SnapTarget(layout: .quarters, zone: 3))
    }

    @Test func eachFrameOfAZoneCanBeLookedUpFromTheTargetThatPicksIt() {
        let area = CGRect(x: 0, y: 0, width: 1512, height: 945)
        let target = SnapTarget(layout: .quarters, zone: 3)
        #expect(target.frame(in: area, gap: 0) == CGRect(x: 756, y: 0, width: 756, height: 473))
    }
}
