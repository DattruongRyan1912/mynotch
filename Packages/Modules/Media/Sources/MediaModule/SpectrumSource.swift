/// Where the levels for the bars come from while the real spectrum is on.
/// A protocol so tests use a fake and never capture system audio or trigger its permission prompt.
protocol SpectrumSource: AnyObject {
    /// Delivers events on the main actor until `stop()`; after `.failed` nothing follows.
    func start(onEvent: @escaping @MainActor (SpectrumEvent) -> Void)
    func stop()
}

nonisolated enum SpectrumEvent: Equatable, Sendable {
    /// One level in 0…1 per band, low to high frequencies, about 30 times a second.
    case bands([Float])
    /// True after more than 10 s of digital silence while running: macOS most likely denied
    /// "System Audio Recording Only". False once sound arrives again.
    case permissionLikelyDenied(Bool)
    /// The tap could not be set up; the reason is for the log.
    case failed(String)
}
