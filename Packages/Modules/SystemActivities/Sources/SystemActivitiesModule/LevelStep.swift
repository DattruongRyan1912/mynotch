/// How far one key press moves a 0...1 level (volume, brightness, keyboard light).
nonisolated enum LevelStep {
    /// The system's own step: sixteen presses from silent to full.
    static let coarse = 16
    /// With ⌥⇧ held.
    static let fine = 64

    static func steps(fine isFine: Bool) -> Int { isFine ? fine : coarse }

    /// The next line of the grid of 1/`steps` in the direction pressed, so a level between lines goes to the nearest
    /// one and a level on a line moves a whole step. Within 0...1.
    static func moved(_ level: Float, up: Bool, steps: Int) -> Float {
        // A level read back from the hardware can be a hair off its line; that hair must not cost a step.
        let tolerance: Float = 0.001
        let scaled = level * Float(steps)
        let target = up ? (scaled + tolerance).rounded(.down) + 1 : (scaled - tolerance).rounded(.up) - 1
        return min(max(target, 0), Float(steps)) / Float(steps)
    }
}
