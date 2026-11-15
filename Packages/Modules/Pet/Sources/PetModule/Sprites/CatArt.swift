import Foundation

/// What the cat does, as pictures. The cat is drawn on a board of 30 by 22 pixels and given a light rim all round, which makes frames
/// of 32 by 24: one pixel to the point on the notch, so two or three device pixels to a pixel of the cat on any display.
///
/// It is drawn in letters (see `CatCoat`), side on when it is going somewhere and facing the viewer when it is not. Its head is typed out
/// (`head`); its body, legs and tail are put together from numbers by `CatCanvas`, which is what lets an animation have as many
/// different frames as it needs.
nonisolated enum CatArt {
    static let width = CatCanvas.width + 2
    static let height = CatCanvas.height + 2

    typealias Point = (x: Double, y: Double)

    // MARK: The face

    enum Face {
        case open, blink, happy, yawn, wide, lookLeft, lookRight, lookUp, sleep, squint
    }

    /// The head, 13 by 11, facing the viewer: pointed ears with pink in them, a round head, eyes with a shine in them, a pink nose, a mouth.
    static func head(_ face: Face) -> [String] {
        var rows = [
            ".KK.......KK.",
            "KPPK.....KPPK",
            "KPPPKKKKKPPPK",
            "KOOOOOOOOOOOK",
            "KOODOOOOODOOK",
            "KOLEOOOOOLEOK",
            "KOEEOOOOOEEOK",
            "KOOOOPPPOOOOK",
            "KOOWWWKWWWOOK",
            ".KOOOOOOOOOK.",
            "..KKKKKKKKK..",
        ]
        switch face {
        case .open: break
        case .blink, .sleep:
            rows[5] = "KOOOOOOOOOOOK"
            rows[6] = "KOKKOOOOOKKOK"
        case .squint:
            rows[5] = "KOOOOOOOOOOOK"
            rows[6] = "KOEEOOOOOEEOK"
        case .happy:
            rows[5] = "KOOKOOOOOKOOK"
            rows[6] = "KOKOKOOOKOKOK"
            rows[7] = "KOPOOPPPOOPOK"
        case .yawn:
            rows[5] = "KOOOOOOOOOOOK"
            rows[6] = "KOKKOOOOOKKOK"
            rows[7] = "KOOOOPPPOOOOK"
            rows[8] = "KOOWKPPPKWOOK"
        case .wide:
            rows[5] = "KOLEEOOOLEEOK"
            rows[6] = "KOEEEOOOEEEOK"
            rows[8] = "KOOWWKPKWWOOK"
        case .lookLeft:
            rows[5] = "KLEOOOOOLEOOK"
            rows[6] = "KEEOOOOOEEOOK"
        case .lookRight:
            rows[5] = "KOOLEOOOOOLEK"
            rows[6] = "KOOEEOOOOOEEK"
        case .lookUp:
            rows[4] = "KOLEOOOOOLEOK"
            rows[5] = "KOEEOOOOOEEOK"
            rows[6] = "KOOOOOOOOOOOK"
        }
        return rows
    }

    // MARK: Finishing

    enum Whiskers {
        case both, right, none
    }

    /// The board with its light rim, and whiskers over the rim (they would be three pixels wide if they had one): `head` is where the head
    /// was put on the board.
    static func finish(_ canvas: CatCanvas, head: (x: Int, y: Int), whiskers: Whiskers = .both) -> PixelFrame {
        var frame = canvas.frame.rimmed(with: "R")
        guard whiskers != .none else { return frame }
        // The head's left and right edges on the finished frame, at the row of the mouth.
        let (left, right) = (head.x + 1, head.x + 13)
        let row = head.y + 1 + 8
        var cells: [(Int, Int)] = []
        for step in 0..<3 {
            if whiskers == .both {
                cells.append((left - step, row - 1))
                cells.append((left - step, row + 1 + (step == 2 ? 1 : 0)))
            }
            cells.append((right + step, row - 1))
            cells.append((right + step, row + 1 + (step == 2 ? 1 : 0)))
        }
        for (x, y) in cells where (0..<frame.width).contains(x) && (0..<frame.height).contains(y) {
            frame = frame.drawing(PixelFrame(width: 1, height: 1, cells: ["V"]), atX: x, y: y)
        }
        return frame
    }

    // MARK: Particles

    static let heart = [".H.H.", "HHHHH", ".HHH.", "..H.."]
    static let zed = ["ZZZZ", "..Z.", ".Z..", "ZZZZ"]
    static let note = [".NN", ".N.", "NN.", "NN."]
    static let bang = ["BB", "BB", "BB", "BB", "..", "BB"]
    static let sweat = [".S.", "SSS", "SSS"]

    // MARK: Parts

    static func stripes(_ canvas: inout CatCanvas, xs: [Int], top: Int, length: Int = 2) {
        for x in xs { canvas.recolour(x: x...x, y: top...(top + length - 1), from: "O", to: "D") }
    }
}
