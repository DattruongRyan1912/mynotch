import Foundation

/// What the capybara plays with: a small round tub of water that comes up out of the floor, ripples while it sits in it and goes again; an
/// orange; and the peel it leaves.
///
/// The tub is drawn over the capybara, so that what is below the water line is behind its front: it is a whole picture, 32 by 24 like the
/// capybara's, whose water is at row `waterLine`, and a character that soaks stands exactly where it is drawn. The orange and the peel are
/// small, with a dark line and a light rim like the cat's yarn and moth.
enum CapybaraProps {
    /// The board row of the water's top, which is the row the back of a capybara in it is above.
    static let waterLine = 14

    // MARK: The tub

    /// The tub at its full size, as board rows: a trapezoid of boards and hoops under a band of water. `ripple` moves the light on the water
    /// and the few wavelets that lap at the capybara's back.
    private static func tubCanvas(ripple: Int) -> CatCanvas {
        var c = CatCanvas()
        let (left, right) = (2, 27)
        // The boards: wider at the top, narrower at the foot.
        for y in (waterLine + 2)...20 {
            let inset = (y - waterLine - 2) / 2
            for x in (left + inset)...(right - inset) { c[x, y] = "T" }
        }
        // Their joints and the hoops.
        for y in (waterLine + 2)...20 {
            let inset = (y - waterLine - 2) / 2
            for x in stride(from: 7, through: 22, by: 5) where (left + inset)...(right - inset) ~= x { c[x, y] = "U" }
            if y == waterLine + 3 || y == 20 { for x in (left + inset)...(right - inset) { c[x, y] = "J" } }
        }
        // The water, two rows deep, in front of the capybara.
        for x in (left + 1)...(right - 1) {
            c[x, waterLine] = (x + 2 * ripple) % 6 < 2 ? "B" : "A"
            c[x, waterLine + 1] = (x + 2 * ripple + 3) % 7 == 0 ? "A" : "C"
        }
        // The line round it.
        for y in waterLine...(waterLine + 1) { c[left, y] = "K"; c[right, y] = "K" }
        c[left, waterLine + 2] = "K"
        c[right, waterLine + 2] = "K"
        for y in (waterLine + 2)...20 {
            let inset = (y - waterLine - 2) / 2
            c[left + inset, y] = "K"
            c[right - inset, y] = "K"
        }
        for x in (left + 3)...(right - 3) { c[x, 21] = "K" }
        c[left + 2, 21] = "K"
        c[right - 2, 21] = "K"
        return c
    }

    /// The tub as a picture, `occupied` or not. A rim goes round it as it does round the capybara; over the water of one with a capybara
    /// in it the rim is left out, because the back comes up through the water there, and a few wavelets lap at it instead. `top` and
    /// `columns` are the part of it that is drawn (the tub comes up out of the floor).
    static func tub(ripple: Int = 0, occupied: Bool = false, from top: Int = 0, between columns: ClosedRange<Int> = 0...29) -> PixelFrame {
        var canvas = tubCanvas(ripple: ripple)
        for y in 0..<CatCanvas.height {
            for x in 0..<CatCanvas.width where y < top || !columns.contains(x) { canvas[x, y] = PixelPalette.clear }
        }
        var frame = canvas.frame.rimmed(with: "R")
        guard occupied else { return frame }
        // The rimmed frame is the board with a pixel more on each side: the row above the water is `waterLine` in it.
        for x in 4...27 where frame[x, waterLine] == "R" { frame = frame.setting(PixelPalette.clear, atX: x, y: waterLine) }
        for x in [5 + (ripple * 5) % 7, 16 + (ripple * 3) % 8] { frame = frame.setting("B", atX: x, y: waterLine) }
        return frame
    }

    /// The tub that comes up out of the floor: a puddle, the foot of it, most of it, and all of it with a spray of drops.
    static let appearing: PixelAnimation = {
        var puddle = CatCanvas()
        puddle.ellipse(cx: 14.5, cy: 19.5, rx: 8, ry: 1.6, fill: "A", outline: "C")
        puddle.piece(["B..B", ".B.."], x: 12, y: 16)
        var spray = tub()
        for (x, y) in [(8, 10), (10, 8), (12, 11), (18, 9), (20, 11), (22, 8), (15, 7)] { spray = spray.setting("B", atX: x, y: y) }
        return PixelAnimation(
            frames: [puddle.frame.rimmed(with: "R"), tub(from: 18, between: 5...24), tub(from: 15, between: 3...26), spray], fps: 6, loops: false
        )
    }()

    /// The tub standing empty.
    static let empty = PixelAnimation(frames: [tub()], fps: 1)

    /// The tub with the light moving over the water and a wavelet or two lapping at the back of whoever is in it.
    static let rippling = PixelAnimation(frames: (0..<4).map { tub(ripple: $0, occupied: true) }, fps: 3)

    /// The tub going back into the floor: the same pictures the other way, and then nothing.
    static let going = PixelAnimation(
        frames: Array(appearing.frames.reversed()) + [PixelFrame(width: 32, height: 24)], fps: 6, loops: false
    )

    // MARK: Oranges

    private static func small(_ rows: [String]) -> PixelFrame {
        do {
            return try PixelFrame(rows: rows, palette: CapybaraArt.palette).rimmed(with: "K").rimmed(with: "R")
        } catch {
            fatalError("The capybara's props are malformed: \(error)")
        }
    }

    /// `frame` in the middle of the foot of a clear picture of the given size: the frames of one strip are all of one size.
    private static func fit(_ frame: PixelFrame, width: Int, height: Int) -> PixelFrame {
        PixelFrame(width: width, height: height).drawing(frame, atX: (width - frame.width) / 2, y: height - frame.height)
    }

    /// An orange: round, with a leaf.
    static let orange = PixelAnimation(frames: [small(CapybaraArt.orange)], fps: 1)

    static let peelSize = (width: 12, height: 8)

    /// A peel: a curl of it lying on the floor, and the same going, smaller, and nothing.
    static let peel = PixelAnimation(frames: [fit(peelPictures[0], width: peelSize.width, height: peelSize.height)], fps: 1)

    static let peelGoing = PixelAnimation(
        frames: peelPictures.map { fit($0, width: peelSize.width, height: peelSize.height) } + [PixelFrame(width: peelSize.width, height: peelSize.height)],
        fps: 6, loops: false
    )

    private static let peelPictures = [
        small(["..GGG...", ".GFFFG..", "GF..GFGG", "G....FFG"]), small(["...G....", "..GFG...", ".GF.FG.."]), small(["..G.", ".GG."]),
    ]
}

extension PixelFrame {
    /// The picture with one pixel changed.
    func setting(_ letter: Character, atX x: Int, y: Int) -> PixelFrame {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return self }
        var cells = self.cells
        cells[y * width + x] = letter
        return PixelFrame(width: width, height: height, cells: cells)
    }
}

extension CapybaraProps {
    /// What the capybara has out, as pictures.
    static func animation(for prop: CapybaraProp) -> PixelAnimation {
        switch prop {
        case .orange: orange
        case .peel: peel
        case .peelGoing: peelGoing
        case .tubAppearing: appearing
        case .tubEmpty: empty
        case .tubRippling: rippling
        case .tubGoing: going
        }
    }
}
