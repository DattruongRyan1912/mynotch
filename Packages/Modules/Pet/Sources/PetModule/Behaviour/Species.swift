import Foundation

/// One kind of character: what decides what it does, and what it looks like. The stage and the views know a species by this and by what
/// it hands them (`CharacterBrain`, `Pose`, strips of pictures), never by what it is.
///
/// To add one: a case in `CharacterKind`, a type that conforms to this (its brain, its moves and its art in files of its own, the way
/// `CatSpecies` is made), and its line in `CharacterKind.species`. Every picture is `CatField.pictureSize` pixels, which is what makes
/// one lane of any mix of them.
///
/// A brain says what its character does as `Pose`s, and keeps to the lane it shares with `LaneKeeper` (where it may stop, how far it may
/// go) made from the `LaneContext` it is given at every update. The stage, the portal, the pointer, the busy Mac and the clock are the
/// stage's: none of it is the species' to do again.
protocol Species: AnyObject {
    /// A new character's brain, standing at `position` (a share of the lane) with its own `seed`.
    func makeBrain(seed: UInt64, now: TimeInterval, position: Double) -> any CharacterBrain

    /// The pictures of one move, side on or facing the viewer, the way `facing` says (the art faces one way and the other is its mirror).
    func strip(for motion: Motion, facing: Facing, appearance: Appearance) -> PixelStrip

    /// The picture a character that does not move at all (Reduce Motion) is drawn from: facing left, towards the camera.
    func restingStrip(appearance: Appearance) -> PixelStrip

    /// What it plays with.
    func propStrip(_ look: PropLook) -> PixelStrip

    /// Whether a click on it mews. A sound is the cat's alone.
    var meowsWhenPetted: Bool { get }
}

extension Species {
    var meowsWhenPetted: Bool { false }
}

extension CharacterKind {
    /// The species of this kind.
    var species: any Species {
        switch self {
        case .cat: CatSpecies.shared
        case .capybara: CapybaraSpecies.shared
        case .hamster: HamsterSpecies.shared
        case .penguin: PenguinSpecies.shared
        case .corgi: CorgiSpecies.shared
        }
    }
}
