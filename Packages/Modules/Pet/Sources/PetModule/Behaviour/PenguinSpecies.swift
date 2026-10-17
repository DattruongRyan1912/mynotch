import Foundation

/// The penguin: the module's fourth species, a clumsy one that goes on its belly, made the way the others are.
final class PenguinSpecies: Species {
    static let shared = PenguinSpecies()

    func makeBrain(seed: UInt64, now: TimeInterval, position: Double) -> any CharacterBrain {
        PenguinBrain(seed: seed, now: now, position: position)
    }

    func strip(for motion: Motion, facing: Facing, appearance: Appearance) -> PixelStrip {
        PenguinSheets.shared.strip(for: PenguinMove(motion), facing: facing)
    }

    func restingStrip(appearance: Appearance) -> PixelStrip {
        PenguinSheets.shared.restingStrip()
    }

    func propStrip(_ look: PropLook) -> PixelStrip {
        PenguinSheets.shared.propStrip(PenguinProp(look))
    }
}

// MARK: The penguin as a character

nonisolated extension PenguinMove {
    /// The move as a view knows it: the number is its place among the penguin's moves.
    var motion: Motion {
        Motion(key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, loops: loops)
    }

    init(_ motion: Motion) {
        self = Self.allCases.indices.contains(motion.key) ? Self.allCases[motion.key] : .stand
    }
}
