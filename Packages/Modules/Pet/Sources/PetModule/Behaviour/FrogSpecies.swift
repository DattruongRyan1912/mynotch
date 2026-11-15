import Foundation

/// The frog: the module's sixth species, a lazy one that sits on a lily pad and catches moths, made the way the others are.
final class FrogSpecies: Species {
    static let shared = FrogSpecies()

    func makeBrain(seed: UInt64, now: TimeInterval, position: Double) -> any CharacterBrain {
        FrogBrain(seed: seed, now: now, position: position)
    }

    func strip(for motion: Motion, facing: Facing, appearance: Appearance) -> PixelStrip {
        FrogSheets.shared.strip(for: FrogMove(motion), facing: facing)
    }

    func restingStrip(appearance: Appearance) -> PixelStrip {
        FrogSheets.shared.restingStrip()
    }

    func propStrip(_ look: PropLook) -> PixelStrip {
        FrogSheets.shared.propStrip(FrogProp(look))
    }
}

// MARK: The frog as a character

nonisolated extension FrogMove {
    /// The move as a view knows it: the number is its place among the frog's moves.
    var motion: Motion {
        Motion(key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, loops: loops)
    }

    init(_ motion: Motion) {
        self = Self.allCases.indices.contains(motion.key) ? Self.allCases[motion.key] : .sit
    }
}
