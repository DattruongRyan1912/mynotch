import AppKit

/// The two moments that may make a sound.
nonisolated enum ClipboardSound: Sendable, Equatable {
    /// An item was captured.
    case captured
    /// MyNotch pasted an item.
    case pasted

    /// A sound that ships with macOS, so nothing is bundled.
    var systemName: String {
        switch self {
        case .captured: "Pop"
        case .pasted: "Tink"
        }
    }
}

/// Plays a sound; a protocol so tests count sounds instead of making them.
protocol ClipboardSoundPlaying {
    func play(_ sound: ClipboardSound)
}

/// Plays nothing: what a module made without a speaker (every test) has.
struct ClipboardSilentPlayer: ClipboardSoundPlaying {
    func play(_ sound: ClipboardSound) {}
}

/// The system sounds, quietly.
struct ClipboardSystemSoundPlayer: ClipboardSoundPlaying {
    static let volume: Float = 0.4

    func play(_ sound: ClipboardSound) {
        guard let player = NSSound(named: NSSound.Name(sound.systemName)) else { return }
        player.volume = Self.volume
        player.play()
    }
}

/// At most one sound in any 300 ms, whichever kind, so a burst of copies, or a paste right after a copy, does not stutter.
nonisolated struct ClipboardSoundGate: Sendable {
    static let interval: Double = 0.3

    private var lastPlayed: Double?

    /// Whether a sound at `time` (monotonic seconds) may play, and counts it if so. A refused sound does not start the wait again,
    /// and a time before the last sound is taken as its time, so a clock that steps back does not let more through.
    mutating func admit(at time: Double) -> Bool {
        let now = max(time, lastPlayed ?? time)
        // A microsecond of slack, so 300 ms after the last sound is not refused for the way seconds are written as fractions.
        if let lastPlayed, now - lastPlayed < Self.interval - 0.000_001 { return false }
        lastPlayed = now
        return true
    }
}
