import Observation

/// Whether the notch is Liquid Glass right now, which the text tokens have to know: they are plain `Color`s that every module
/// reads, and no environment reaches a constant. A view that reads a token in its body reads this too, so it is drawn again
/// when the look changes. A colour a module captured once (a layer's colour, a `static let`) keeps what it had.
@Observable
final class NotchLookState {
    /// The app's. `ScreenManager`'s theme keeps it in step with the setting; nothing else changes it.
    static let shared = NotchLookState()

    /// What the tokens read. A test binds a state of its own for the duration of a call, so a test can never flip the app's
    /// for the ones that run beside it.
    @TaskLocal static var current: NotchLookState = .shared

    var isGlass = false
}
