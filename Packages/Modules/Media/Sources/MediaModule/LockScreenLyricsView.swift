import AppKit
import NotchUI
import SwiftUI

extension KaraokeStyle {
    /// The current line on the lock screen: a little larger than the strip's, the sung part lit and the rest dimmed.
    static let lockScreen = KaraokeStyle(fontSize: LockScreenLyricsView.currentSize, weight: .semibold, lit: NSColor(NotchTokens.primaryText), dim: NSColor(NotchTokens.secondaryText))
}

/// Under the track on the lock screen: the line being sung (filled word by word when its words are timed, else lit whole) and the
/// next one dimmed, centred, one row each. The card can stay up for hours, so it costs what the notch's strip does and no more:
/// a timeline that ticks only when the position reaches a line (`LyricTimeline`), and one animation for the fill that the render
/// server runs; nothing is redrawn per frame, and all of it stands still while `notchIsOnScreen` is false (the display sleeps).
struct LockScreenLyricsView: View {
    static let currentSize: CGFloat = 14
    static let currentFont = Font.system(size: currentSize, weight: .semibold)
    static let nextHeight: CGFloat = 15
    static let spacing: CGFloat = 2
    static var currentHeight: CGFloat { KaraokeStyle.lockScreen.lineHeight }
    /// Both rows, and never more or less, so the card does not jump at each pause in the song.
    static var height: CGFloat { currentHeight + spacing + nextHeight }

    let store: NowPlayingStore
    /// Called at every evaluation of the timeline's content, with its date; tests count them.
    var onEvaluate: (Date) -> Void = { _ in }

    var body: some View {
        LyricTimeline(store: store) { date in
            let _ = onEvaluate(date)
            rows(store.lockScreenLyrics(at: date) ?? LockScreenLyrics(current: .note, next: nil))
        }
    }

    private func rows(_ lyrics: LockScreenLyrics) -> some View {
        VStack(spacing: Self.spacing) {
            current(lyrics.current)
                .frame(height: Self.currentHeight)
            Text(lyrics.next ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(CGFloat(KaraokeFit.minimumScale))
                .frame(maxWidth: .infinity, minHeight: Self.nextHeight, maxHeight: Self.nextHeight)
        }
        .frame(maxWidth: .infinity)
        // One element that reads the lines, never the note.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lời bài hát")
        .accessibilityValue(lyrics.spoken)
    }

    @ViewBuilder
    private func current(_ current: LockScreenLyrics.Current) -> some View {
        switch current {
        case .sweep(let line):
            KaraokeLine(line: line, store: store, style: .lockScreen)
        case .whole(let text):
            Text(text)
                .font(Self.currentFont)
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(CGFloat(KaraokeFit.minimumScale))
                .frame(maxWidth: .infinity)
        case .note:
            Text(LyricStrip.note)
                .font(Self.currentFont)
                .foregroundStyle(NotchTokens.secondaryText)
        }
    }
}
