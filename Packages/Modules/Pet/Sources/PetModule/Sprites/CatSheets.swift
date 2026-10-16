import CoreGraphics
import Foundation

/// The strips of images the cat's animations are played from, made when first asked for and kept: they are the same for every display.
/// A coat makes a set of its own, and only the one in use is ever made.
final class CatSheets {
    struct Key: Hashable {
        let move: CatMove
        let facing: Facing
        let coat: CatCoat
    }

    static let shared = CatSheets()

    private var strips: [Key: PixelStrip] = [:]
    private var resting: [CatCoat: PixelStrip] = [:]
    private var props: [PropKind: PixelStrip] = [:]

    /// How many strips have been made, for tests: they are made once, however many displays show them.
    private(set) var builds = 0
    /// The bytes of image all of them hold.
    private(set) var bytes = 0

    /// The strip of `move` facing `facing`; the sprites face right and the mirror image is made for left.
    func strip(for move: CatMove, facing: Facing, coat: CatCoat) -> PixelStrip {
        let key = Key(move: move, facing: facing, coat: coat)
        if let cached = strips[key] { return cached }
        let strip = make(CatArt.animation(for: move).frames, facing: facing, palette: coat.palette)
        strips[key] = strip
        return strip
    }

    /// The sitting cat with its eyes open and shut, for a cat that does not move (Reduce Motion): always facing left, towards the camera.
    func restingStrip(coat: CatCoat) -> PixelStrip {
        if let cached = resting[coat] { return cached }
        let strip = make(CatArt.restingFrames, facing: .left, palette: coat.palette)
        resting[coat] = strip
        return strip
    }

    func propStrip(_ kind: PropKind) -> PixelStrip {
        if let cached = props[kind] { return cached }
        let frames = kind == .moth ? PropArt.moth.frames : PropArt.yarn.frames
        let strip = make(frames, facing: .right, palette: CatCoat.tabby.palette)
        props[kind] = strip
        return strip
    }

    private func make(_ frames: [PixelFrame], facing: Facing, palette: PixelPalette) -> PixelStrip {
        let ordered = facing == .left ? frames.map(\.mirrored) : frames
        guard let strip = PixelStrip(frames: ordered, palette: palette) else {
            fatalError("The system could not make an image of the cat")
        }
        builds += 1
        bytes += strip.byteCount
        return strip
    }
}
