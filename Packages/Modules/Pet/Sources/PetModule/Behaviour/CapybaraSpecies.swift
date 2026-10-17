import Foundation

/// The capybara: the module's second species, a calm one, made the way the cat is.
final class CapybaraSpecies: Species {
    static let shared = CapybaraSpecies()

    func makeBrain(seed: UInt64, now: TimeInterval, position: Double) -> any CharacterBrain {
        CapybaraBrain(seed: seed, now: now, position: position)
    }

    func strip(for motion: Motion, facing: Facing, appearance: Appearance) -> PixelStrip {
        CapybaraSheets.shared.strip(for: CapybaraMove(motion), facing: facing)
    }

    func restingStrip(appearance: Appearance) -> PixelStrip {
        CapybaraSheets.shared.restingStrip()
    }

    func propStrip(_ look: PropLook) -> PixelStrip {
        CapybaraSheets.shared.propStrip(CapybaraProp(look))
    }
}

// MARK: The capybara as a character

nonisolated extension CapybaraMove {
    /// The move as a view knows it: the number is its place among the capybara's moves.
    var motion: Motion {
        Motion(key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, loops: loops)
    }

    init(_ motion: Motion) {
        self = Self.allCases.indices.contains(motion.key) ? Self.allCases[motion.key] : .sit
    }
}

/// What the capybara has out, as a view knows it. The tub is drawn over the capybara, so what is under its water line is behind it.
nonisolated enum CapybaraProp: CaseIterable, Equatable, Sendable {
    case orange, peel, peelGoing
    /// The tub coming up out of the floor, standing empty, with someone in it and going back into the floor.
    case tubAppearing, tubEmpty, tubRippling, tubGoing

    /// The pictures of it: the art makes exactly this many (tested), and the brain, which must not build the art to plan, counts on them.
    var frameCount: Int {
        switch self {
        case .orange, .peel, .tubEmpty: 1
        case .peelGoing, .tubAppearing, .tubRippling: 4
        case .tubGoing: 5
        }
    }

    var fps: Double {
        switch self {
        case .orange, .peel, .tubEmpty: 1
        case .tubRippling: 3
        case .peelGoing, .tubAppearing, .tubGoing: 6
        }
    }

    /// Time one pass takes: what a tub that comes up or goes takes, and the pose that shows it lasts.
    var passDuration: TimeInterval { Double(frameCount) / fps }

    var look: PropLook {
        PropLook(
            key: Self.allCases.firstIndex(of: self) ?? 0, fps: fps, rise: self == .orange || self == .peel || self == .peelGoing ? 1 : 0,
            animatesInPlace: [.peelGoing, .tubAppearing, .tubRippling, .tubGoing].contains(self),
            loops: ![.peelGoing, .tubAppearing, .tubGoing].contains(self), occupies: [.tubAppearing, .tubEmpty, .tubRippling, .tubGoing].contains(self)
        )
    }

    init(_ look: PropLook) {
        self = Self.allCases.indices.contains(look.key) ? Self.allCases[look.key] : .orange
    }
}
