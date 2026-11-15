import Foundation

/// The corgi: the module's fifth species, a hyperactive one that plays fetch, made the way the others are.
final class CorgiSpecies: Species {
    static let shared = CorgiSpecies()

    func makeBrain(seed: UInt64, now: TimeInterval, position: Double) -> any CharacterBrain {
        CorgiBrain(seed: seed, now: now, position: position)
    }

    func strip(for motion: Motion, facing: Facing, appearance: Appearance) -> PixelStrip {
        CorgiSheets.shared.strip(for: CorgiMove(motion), facing: facing)
    }

    func restingStrip(appearance: Appearance) -> PixelStrip {
        CorgiSheets.shared.restingStrip()
    }

    func propStrip(_ look: PropLook) -> PixelStrip {
        CorgiSheets.shared.propStrip(CorgiProp(look))
    }
}

// MARK: The corgi as a character

nonisolated extension CorgiMove {
    /// The move as a view knows it: the number is its place among the corgi's moves.
    var motion: Motion {
        Motion(key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, loops: loops)
    }

    init(_ motion: Motion) {
        self = Self.allCases.indices.contains(motion.key) ? Self.allCases[motion.key] : .stand
    }
}
