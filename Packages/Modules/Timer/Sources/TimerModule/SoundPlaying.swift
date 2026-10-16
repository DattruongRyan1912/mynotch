import AppKit

/// Plays a named system sound. Injected so tests stay silent.
protocol SoundPlaying: AnyObject {
    func play(named name: String)
    /// Cuts off the sound that is playing, if any.
    func stop()
}

final class SystemSoundPlayer: SoundPlaying {
    /// Held while it plays: a sound nobody holds can stop before it ends.
    private var current: NSSound?

    /// `NSSound(named:)` hands out one shared instance per name, and `play()` on an instance that is still playing does
    /// nothing, so the one that plays is stopped first.
    func play(named name: String) {
        current?.stop()
        current = NSSound(named: name)
        current?.play()
    }

    func stop() {
        current?.stop()
        current = nil
    }
}
