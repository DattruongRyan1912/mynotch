import Foundation

/// What the cat plays with: a moth that flutters (two frames) and a ball of yarn that rolls (four). Drawn small, with a dark line and a
/// light rim round them like the cat, so they read on the same grounds.
nonisolated enum PropArt {
    private static func frame(_ rows: [String], rim: Bool = true) -> PixelFrame {
        do {
            let art = try PixelFrame(rows: rows, palette: CatCoat.tabby.palette)
            return rim ? art.rimmed(with: "K").rimmed(with: "R") : art.rimmed(with: "K")
        } catch {
            fatalError("The props' art is malformed: \(error)")
        }
    }

    /// Wings up, then wings down.
    static let moth = PixelAnimation(
        frames: [
            frame(["MM.....MM", "MMM.A.MMM", ".MMMAMMM.", "...MAM...", "....A...."], rim: false),
            frame(["....A....", ".MM.A.MM.", "MMMMAMMMM", ".MMMAMMM.", "..MM.MM.."], rim: false),
        ],
        fps: 10
    )

    static let mothSize = CGSize(width: moth.frames[0].width, height: moth.frames[0].height)

    /// A ball of yarn: a round with windings that move round it as it rolls.
    static func yarn(turn: Int) -> PixelFrame {
        let size = 8
        var rows: [String] = []
        for y in 0..<size {
            var row = ""
            for x in 0..<size {
                let (dx, dy) = (Double(x) + 0.5 - 4, Double(y) + 0.5 - 4)
                if dx * dx + dy * dy > 15.5 {
                    row.append(".")
                } else {
                    row.append((x + y + turn) % 4 == 0 ? "U" : "Y")
                }
            }
            rows.append(row)
        }
        return frame(rows)
    }

    static let yarn = PixelAnimation(frames: (0..<4).map { yarn(turn: $0) }, fps: 12)

    static let yarnSize = CGSize(width: yarn.frames[0].width, height: yarn.frames[0].height)
}
