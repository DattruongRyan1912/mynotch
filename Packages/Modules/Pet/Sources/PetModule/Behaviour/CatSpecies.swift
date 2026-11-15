import Foundation

/// The cat: the module's first species, and the one every other is made like.
final class CatSpecies: Species {
    static let shared = CatSpecies()

    var meowsWhenPetted: Bool { true }

    func makeBrain(seed: UInt64, now: TimeInterval, position: Double) -> any CharacterBrain {
        CatBrain(seed: seed, now: now, position: position)
    }

    func strip(for motion: Motion, facing: Facing, appearance: Appearance) -> PixelStrip {
        CatSheets.shared.strip(for: CatMove(motion), facing: facing, coat: appearance.coat)
    }

    func restingStrip(appearance: Appearance) -> PixelStrip {
        CatSheets.shared.restingStrip(coat: appearance.coat)
    }

    func propStrip(_ look: PropLook) -> PixelStrip {
        CatSheets.shared.propStrip(PropKind(look))
    }
}

// MARK: The cat as a character

nonisolated extension CatMove {
    /// The move as a view knows it: the number is its place among the cat's moves.
    var motion: Motion {
        Motion(key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, loops: loops, sinks: self == .peek)
    }

    init(_ motion: Motion) {
        self = Self.allCases.indices.contains(motion.key) ? Self.allCases[motion.key] : .sit
    }
}

nonisolated extension PropKind {
    /// How a moth and a ball of yarn are played, as a view knows them.
    var look: PropLook {
        switch self {
        case .moth: PropLook(key: 0, fps: PropArt.moth.fps, flutters: true, rise: PropArt.mothRise, animatesInPlace: true)
        case .yarn: PropLook(key: 1, fps: PropArt.yarn.fps)
        }
    }

    init(_ look: PropLook) {
        self = look.key == 0 ? .moth : .yarn
    }
}

nonisolated extension CatPlan {
    /// The plan as a view and the stage see it.
    var pose: Pose {
        Pose(
            motion: move.motion, facing: facing, from: from, to: to, began: began, duration: duration, fpsScale: fpsScale, delay: delay,
            prop: prop.map { PoseProp(look: $0.kind.look, from: $0.from, to: $0.to) }, raised: move.ridesOn
        )
    }
}

nonisolated extension CatBrain: CharacterBrain {
    var pose: Pose {
        var pose = plan.pose
        // The place the cat goes to when it is done with the capybara is kept free for it.
        pose.reserves = jointExit.map { [$0] } ?? []
        return pose
    }
}
