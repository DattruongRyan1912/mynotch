import Foundation

/// The portal the cat goes into at one edge of the camera and comes out of at the other: a ring of violet with a light inner edge, a
/// swirl of cyan inside it, drawn in four pictures. The first is clear (a portal that is not open), then the portal opening, and two
/// pictures of it swirling, which are played one after the other. The same size for both edges: a portal is as tall as the cat.
nonisolated enum PortalArt {
    static let width = CatField.portalWidth
    static let height = Int(CatField.pictureSize.height)

    /// Which picture is which, in the strip.
    static let clear = 0
    static let opening = 1
    static let swirlA = 2
    static let swirlB = 3

    private static func ring(rx: Double, ry: Double, phase: Double) -> PixelFrame {
        let (cx, cy) = (Double(width) / 2, Double(height) / 2)
        var rows: [String] = []
        for y in 0..<height {
            var row = ""
            for x in 0..<width {
                let (dx, dy) = ((Double(x) + 0.5 - cx) / rx, (Double(y) + 0.5 - cy) / ry)
                let distance = dx * dx + dy * dy
                if distance > 1 {
                    row.append(PixelPalette.clear)
                } else if distance > 0.55 {
                    row.append("Q")
                } else if distance > 0.4 {
                    row.append("I")
                } else {
                    // Two arms of a spiral, which turns from one picture to the next.
                    let turn = (atan2(dy, dx) / (2 * .pi) + 1 + distance * 1.4 + phase).truncatingRemainder(dividingBy: 1)
                    row.append(turn < 0.5 ? "C" : PixelPalette.clear)
                }
            }
            rows.append(row)
        }
        do {
            return try PixelFrame(rows: rows, palette: CatCoat.tabby.palette)
        } catch {
            fatalError("The portal's art is malformed: \(error)")
        }
    }

    static let frames: [PixelFrame] = [
        PixelFrame(width: width, height: height),
        ring(rx: 2.4, ry: 7, phase: 0),
        ring(rx: 4.7, ry: 11.7, phase: 0),
        ring(rx: 4.7, ry: 11.7, phase: 0.25),
    ]
}
