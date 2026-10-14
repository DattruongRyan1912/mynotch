import AppKit
import SwiftUI
import Testing
@testable import WindowLayoutModule

/// The row drawn offscreen (no window, no screen): SwiftUI has to put every tile and every lit zone where `SnapTiles` says
/// it is, because the drop is decided from those frames and the picture comes from SwiftUI.
@Suite struct SnapTilesViewTests {
    let size = CGSize(width: 556, height: SnapTiles.height)

    func render(_ model: SnapTilesModel, height: CGFloat = SnapTiles.height) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: SnapTilesView(model: model).frame(width: size.width, height: height))
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    func model(_ layouts: [SnapLayout], hovered: SnapTarget? = nil) -> SnapTilesModel {
        let model = SnapTilesModel()
        model.layouts = layouts
        model.hovered = hovered
        return model
    }

    /// Runs of drawn pixels along the row `y` points from the top, as x ranges.
    func runs(in bitmap: NSBitmapImageRep, y: Int) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for x in 0..<bitmap.pixelsWide {
            let drawn = (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01
            if drawn, start == nil { start = x }
            if !drawn, let begin = start {
                runs.append(begin...(x - 1))
                start = nil
            }
        }
        if let begin = start { runs.append(begin...(bitmap.pixelsWide - 1)) }
        return runs
    }

    @Test func eachTileIsDrawnWhereTheFramesSay() throws {
        for layouts in [SnapLayout.allCases, [.rightHalf, .thirds], [.focus]] {
            let bitmap = try render(model(layouts))
            #expect(bitmap.pixelsWide == 556 && bitmap.pixelsHigh == Int(SnapTiles.height))
            let frames = SnapTiles.frames(count: layouts.count, in: CGRect(origin: .zero, size: size))
            // Low in the tile, under its title, where nothing but the tile's own fill is.
            let found = runs(in: bitmap, y: 78)
            #expect(found.count == layouts.count, "\(layouts)")
            for (run, frame) in zip(found, frames) {
                #expect(abs(CGFloat(run.lowerBound) - frame.minX) <= 1 && abs(CGFloat(run.upperBound + 1) - frame.maxX) <= 1, "\(run) vs \(frame)")
            }
        }
    }

    @Test func theRowKeepsItsHeightWhateverRoomTheNotchGivesItAndStaysAtTheTop() throws {
        // A notch over a tall tab gives its content more height than the row needs.
        let bitmap = try render(model(SnapLayout.allCases), height: 176)
        #expect(bitmap.pixelsHigh == 176)
        #expect(runs(in: bitmap, y: 78).count == 6)
        #expect(runs(in: bitmap, y: Int(SnapTiles.height) + 6).isEmpty, "nothing under the row")
        #expect(runs(in: bitmap, y: Int(SnapTiles.height) - 2).count == 6, "the row reaches its full height")
    }

    /// The colour of the picture of `tile` at `unit` (fractions of it, y down).
    func colour(_ bitmap: NSBitmapImageRep, tile: CGRect, at unit: CGPoint) -> NSColor? {
        let glyph = SnapTiles.glyphFrame(in: tile)
        // The picture is measured from the bottom of the content rect: AppKit's y, here counted from the top of the image.
        let x = glyph.minX + unit.x * glyph.width
        let yFromTop = size.height - (glyph.maxY - unit.y * glyph.height)
        return bitmap.colorAt(x: Int(x), y: Int(yFromTop))
    }

    @Test func theZoneUnderThePointerIsTheOneLit() throws {
        let content = CGRect(origin: .zero, size: size)
        let tile = SnapTiles.frames(count: 6, in: content)[3]
        for lit in 0..<4 {
            let bitmap = try render(model(SnapLayout.allCases, hovered: SnapTarget(layout: .quarters, zone: lit)))
            let centres = [CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.75, y: 0.25), CGPoint(x: 0.25, y: 0.75), CGPoint(x: 0.75, y: 0.75)]
            let greens = try centres.map { try #require(colour(bitmap, tile: tile, at: $0)).greenComponent }
            // The accent is the one with the least green; the others are pale.
            #expect(greens.indices.min { greens[$0] < greens[$1] } == lit, "zone \(lit): \(greens)")
        }
    }

    @Test func aTileThatIsNotHoveredLightsNothing() throws {
        let bitmap = try render(model(SnapLayout.allCases, hovered: SnapTarget(layout: .thirds, zone: 1)))
        let content = CGRect(origin: .zero, size: size)
        let quarters = SnapTiles.frames(count: 6, in: content)[3]
        let greens = try [CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.75, y: 0.75)].map {
            try #require(colour(bitmap, tile: quarters, at: $0)).greenComponent
        }
        #expect(greens[0] == greens[1], "no zone of the quarters tile is lit")
        let thirds = SnapTiles.frames(count: 6, in: content)[4]
        let lit = try #require(colour(bitmap, tile: thirds, at: CGPoint(x: 0.5, y: 0.5))).greenComponent
        let dim = try #require(colour(bitmap, tile: thirds, at: CGPoint(x: 0.17, y: 0.5))).greenComponent
        #expect(lit < dim, "the middle third of the thirds tile is the lit one")
    }

    @Test func noLayoutsDrawNothing() throws {
        // Over a solid colour: a renderer hands back stale pixels for an image with nothing drawn at all.
        let renderer = ImageRenderer(content: SnapTilesView(model: model([])).frame(width: size.width, height: size.height).background(Color(.sRGB, red: 0, green: 0, blue: 1)))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        for (x, y) in [(10, 10), (100, 44), (300, 78), (545, 80)] {
            let colour = try #require(bitmap.colorAt(x: x, y: y))
            #expect(colour.blueComponent > 0.9 && colour.redComponent < 0.1 && colour.greenComponent < 0.1, "\(x),\(y)")
        }
    }
}
