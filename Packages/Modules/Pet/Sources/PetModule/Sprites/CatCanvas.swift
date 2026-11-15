import Foundation

/// A little drawing board for the cat: shapes in letters of the palette, put one over another from the back to the front. The cat's
/// body, legs and tail are drawn with it from a handful of numbers a pose (where a foot is, how the tail bends), which is what lets
/// an animation have as many different frames as it needs without every one being typed out; its head is typed out.
nonisolated struct CatCanvas {
    static let width = 30
    static let height = 22

    private(set) var cells = [Character](repeating: PixelPalette.clear, count: width * height)

    subscript(x: Int, y: Int) -> Character {
        get { (0..<Self.width).contains(x) && (0..<Self.height).contains(y) ? cells[y * Self.width + x] : PixelPalette.clear }
        set {
            guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else { return }
            cells[y * Self.width + x] = newValue
        }
    }

    var frame: PixelFrame { PixelFrame(width: Self.width, height: Self.height, cells: cells) }

    /// Rows of letters with their top left at (`x`, `y`); a clear pixel leaves what is under it.
    mutating func piece(_ rows: [String], x: Int, y: Int) {
        for (dy, row) in rows.enumerated() {
            for (dx, letter) in row.enumerated() where letter != PixelPalette.clear { self[x + dx, y + dy] = letter }
        }
    }

    /// A solid ellipse with a line round it.
    mutating func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, fill: Character, outline: Character) {
        func inside(_ x: Int, _ y: Int, _ extra: Double) -> Bool {
            let (dx, dy) = ((Double(x) + 0.5 - cx) / (rx + extra), (Double(y) + 0.5 - cy) / (ry + extra))
            return dx * dx + dy * dy <= 1
        }
        for y in 0..<Self.height {
            for x in 0..<Self.width where inside(x, y, 1) { self[x, y] = inside(x, y, 0) ? fill : outline }
        }
    }

    /// A thick line along `points`, `width` pixels wide, with a line round it; the last `paw` pixels of it, if `paw` is given, are drawn in
    /// that letter. What the line is drawn over stays under it, and its outline cuts what it passes over.
    mutating func stroke(_ points: [(x: Double, y: Double)], width: Int, fill: Character, outline: Character, paw: Character? = nil, pawLength: Int = 2) {
        guard let first = points.first else { return }
        var stamped = Set<Int>()
        var order: [Int] = []
        func stamp(_ x: Double, _ y: Double) {
            let (left, top) = (Int((x - Double(width) / 2 + 0.5).rounded(.down)), Int((y - Double(width) / 2 + 0.5).rounded(.down)))
            for dy in 0..<width {
                for dx in 0..<width {
                    let (px, py) = (left + dx, top + dy)
                    guard (0..<Self.width).contains(px), (0..<Self.height).contains(py) else { continue }
                    if stamped.insert(py * Self.width + px).inserted { order.append(py * Self.width + px) }
                }
            }
        }
        stamp(first.x, first.y)
        for (from, to) in zip(points, points.dropFirst()) {
            let length = max(abs(to.x - from.x), abs(to.y - from.y))
            let steps = max(Int((length * 3).rounded(.up)), 1)
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                stamp(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t)
            }
        }
        // The outline first, so that the fill is never cut by it.
        for index in order {
            let (x, y) = (index % Self.width, index / Self.width)
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] where !stamped.contains((y + dy) * Self.width + x + dx) {
                self[x + dx, y + dy] = outline
            }
        }
        for index in order { self[index % Self.width, index / Self.width] = fill }
        if let paw, let last = points.last {
            for index in order {
                let (x, y) = (index % Self.width, index / Self.width)
                if abs(Double(x) + 0.5 - last.x) <= Double(width) / 2 + 0.01, abs(Double(y) + 0.5 - last.y) <= Double(pawLength) / 2 + 0.5 {
                    self[x, y] = paw
                }
            }
        }
    }

    /// `letter` in the pixels of `columns` and `rows` that are `from` (stripes on a coat, which stay inside the body).
    mutating func recolour(x: ClosedRange<Int>, y: ClosedRange<Int>, from: Character, to letter: Character) {
        for row in y { for column in x where self[column, row] == from { self[column, row] = letter } }
    }
}
