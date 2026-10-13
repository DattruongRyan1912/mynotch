import AppKit

/// Plays a named system sound. Injected so tests stay silent.
protocol SoundPlaying: AnyObject {
    func play(named name: String)
}

final class SystemSoundPlayer: SoundPlaying {
    func play(named name: String) { NSSound(named: name)?.play() }
}
