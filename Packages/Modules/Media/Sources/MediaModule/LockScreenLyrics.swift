import AppKit

/// The two lines under the track on the lock screen at one moment: the one being sung and the one coming next, which skips pauses.
/// Lyrics are public text, so this is all the lock screen learns of them.
struct LockScreenLyrics: Equatable {
    /// How the line being sung is drawn.
    enum Current: Equatable {
        /// Word by word: the fill the render server runs (R3c's `KaraokeLine`).
        case sweep(LyricLine)
        /// The whole line, lit: it has no word timing, the sweep is off, or it runs right to left and no left-to-right fill can follow it.
        case whole(String)
        /// Nothing is sung: before the first line and in a pause. Drawn as the dimmed note.
        case note
    }

    var current: Current
    var next: String?

    init(current: Current, next: String?) {
        self.current = current
        self.next = next
    }

    /// `position` nil is a clock that knows no elapsed time yet: only the note is shown. `sweeps` is whether lines are filled word
    /// by word at all (`NowPlayingStore.karaokeIsActive`).
    init(lines: [LyricLine], position: Double?, sweeps: Bool) {
        let around = LyricPanelLines(lines: lines, position: position)
        next = around.next?.text
        guard let line = around.current else {
            current = .note
            return
        }
        let sweepable = sweeps && line.words != nil && !KaraokeFit.hasRightToLeftRun(line.text, font: KaraokeStyle.lockScreen.font)
        current = sweepable ? .sweep(line) : .whole(line.text)
    }

    /// What VoiceOver reads: the lines, never the note.
    var spoken: String {
        var texts: [String] = []
        switch current {
        case .sweep(let line): texts.append(line.text)
        case .whole(let text): texts.append(text)
        case .note: break
        }
        if let next { texts.append(next) }
        return texts.joined(separator: ", ")
    }
}

extension NowPlayingStore {
    /// The lock screen's two lines at `date`; nil while the track has no synced lyrics. The row's "hide lyrics" button is for the
    /// notch: the lock screen has its own switch, as the floating panel is a choice of its own.
    func lockScreenLyrics(at date: Date) -> LockScreenLyrics? {
        guard let syncedLyrics else { return nil }
        return LockScreenLyrics(lines: syncedLyrics, position: position(at: date), sweeps: karaokeIsActive)
    }
}
