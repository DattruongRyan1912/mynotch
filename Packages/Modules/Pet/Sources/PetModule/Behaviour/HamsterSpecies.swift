import Foundation

/// The hamster: the module's third species, a busy one, made the way the cat and the capybara are.
final class HamsterSpecies: Species {
    static let shared = HamsterSpecies()

    func makeBrain(seed: UInt64, now: TimeInterval, position: Double) -> any CharacterBrain {
        HamsterBrain(seed: seed, now: now, position: position)
    }

    func strip(for motion: Motion, facing: Facing, appearance: Appearance) -> PixelStrip {
        HamsterSheets.shared.strip(for: HamsterMove(motion), facing: facing)
    }

    func restingStrip(appearance: Appearance) -> PixelStrip {
        HamsterSheets.shared.restingStrip()
    }

    func propStrip(_ look: PropLook) -> PixelStrip {
        HamsterSheets.shared.propStrip(HamsterProp(look))
    }
}

// MARK: The hamster as a character

nonisolated extension HamsterMove {
    /// The move as a view knows it: the number is its place among the hamster's moves.
    var motion: Motion {
        Motion(key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, loops: loops)
    }

    init(_ motion: Motion) {
        self = Self.allCases.indices.contains(motion.key) ? Self.allCases[motion.key] : .sit
    }
}
