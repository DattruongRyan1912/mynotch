import CoreGraphics
import Foundation

/// The strips of images the frog's animations are played from, made when first asked for and kept: they are the same for every display.
/// The moth it hunts is the cat's, and its strip is the cat's own (`CatSheets`): a moth drawn in the frog's colours would be a moth drawn in
/// letters the frog's palette does not have.
final class FrogSheets {
    struct Key: Hashable {
        let move: FrogMove
        let facing: Facing
    }

    static let shared = FrogSheets()

    private var strips: [Key: PixelStrip] = [:]
    private var resting: PixelStrip?
    private var props: [FrogProp: PixelStrip] = [:]

    /// How many strips have been made, for tests: they are made once, however many displays show them.
    private(set) var builds = 0
    /// The bytes of image all of them hold.
    private(set) var bytes = 0

    /// The strip of `move` facing `facing`; the sprites face right and the mirror image is made for left.
    func strip(for move: FrogMove, facing: Facing) -> PixelStrip {
        let key = Key(move: move, facing: facing)
        if let cached = strips[key] { return cached }
        let strip = make(FrogArt.animation(for: move).frames, facing: facing)
        strips[key] = strip
        return strip
    }

    /// The sitting frog with its eyes open and shut, for one that does not move (Reduce Motion): facing left, towards the camera.
    func restingStrip() -> PixelStrip {
        if let resting { return resting }
        let strip = make(FrogArt.restingFrames, facing: .left)
        resting = strip
        return strip
    }

    func propStrip(_ prop: FrogProp) -> PixelStrip {
        if prop.isMoth { return CatSheets.shared.propStrip(.moth) }
        if let cached = props[prop] { return cached }
        guard let animation = FrogProps.animation(for: prop) else { fatalError("The frog has no picture of \(prop)") }
        let strip = make(animation.frames, facing: .right)
        props[prop] = strip
        return strip
    }

    private func make(_ frames: [PixelFrame], facing: Facing) -> PixelStrip {
        let ordered = facing == .left ? frames.map(\.mirrored) : frames
        guard let strip = PixelStrip(frames: ordered, palette: FrogArt.palette) else {
            fatalError("The system could not make an image of the frog")
        }
        builds += 1
        bytes += strip.byteCount
        return strip
    }
}
