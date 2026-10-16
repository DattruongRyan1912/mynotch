import CoreGraphics
import Foundation

/// The strips of images the cat's animations are played from, made when first asked for and kept: they are the same for every display.
final class CatSheets {
    struct Key: Hashable {
        let pose: CatPose
        let facing: Facing
    }

    static let shared = CatSheets()

    private var strips: [Key: PixelStrip] = [:]
    private var resting: [Facing: PixelStrip] = [:]

    /// How many strips have been made, for tests: they are made once, however many displays show them.
    private(set) var builds = 0

    /// The strip of `pose` facing `facing`; the sprites face right and the mirror image is made for left.
    func strip(for pose: CatPose, facing: Facing) -> PixelStrip {
        let key = Key(pose: pose, facing: facing)
        if let cached = strips[key] { return cached }
        let animation = CatArt.animation(for: pose)
        let strip = Self.make(animation.frames, facing: facing)
        strips[key] = strip
        builds += 1
        return strip
    }

    /// The sitting cat with its eyes open and shut, for a cat that does not move (Reduce Motion): always facing left, towards the camera.
    func restingStrip() -> PixelStrip {
        if let cached = resting[.left] { return cached }
        let strip = Self.make(CatArt.restingFrames, facing: .left)
        resting[.left] = strip
        builds += 1
        return strip
    }

    private static func make(_ frames: [PixelFrame], facing: Facing) -> PixelStrip {
        let ordered = facing == .left ? frames.map(\.mirrored) : frames
        guard let strip = PixelStrip(frames: ordered, palette: CatArt.palette) else {
            fatalError("The system could not make an image of the cat")
        }
        return strip
    }
}
