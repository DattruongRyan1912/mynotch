import CoreGraphics
import Foundation

/// The strips of images the hamster's animations are played from, made when first asked for and kept: they are the same for every display.
final class HamsterSheets {
    struct Key: Hashable {
        let move: HamsterMove
        let facing: Facing
    }

    static let shared = HamsterSheets()

    private var strips: [Key: PixelStrip] = [:]
    private var resting: PixelStrip?
    private var props: [HamsterProp: PixelStrip] = [:]

    /// How many strips have been made, for tests: they are made once, however many displays show them.
    private(set) var builds = 0
    /// The bytes of image all of them hold.
    private(set) var bytes = 0

    /// The strip of `move` facing `facing`; the sprites face right and the mirror image is made for left.
    func strip(for move: HamsterMove, facing: Facing) -> PixelStrip {
        let key = Key(move: move, facing: facing)
        if let cached = strips[key] { return cached }
        let strip = make(HamsterArt.animation(for: move).frames, facing: facing)
        strips[key] = strip
        return strip
    }

    /// The sitting hamster with its eyes open and shut, for one that does not move (Reduce Motion): facing left, towards the camera.
    func restingStrip() -> PixelStrip {
        if let resting { return resting }
        let strip = make(HamsterArt.restingFrames, facing: .left)
        resting = strip
        return strip
    }

    func propStrip(_ prop: HamsterProp) -> PixelStrip {
        if let cached = props[prop] { return cached }
        let strip = make(HamsterProps.animation(for: prop).frames, facing: .right)
        props[prop] = strip
        return strip
    }

    private func make(_ frames: [PixelFrame], facing: Facing) -> PixelStrip {
        let ordered = facing == .left ? frames.map(\.mirrored) : frames
        guard let strip = PixelStrip(frames: ordered, palette: HamsterArt.palette) else {
            fatalError("The system could not make an image of the hamster")
        }
        builds += 1
        bytes += strip.byteCount
        return strip
    }
}
