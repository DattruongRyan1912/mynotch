import NotchUI
import SwiftUI

/// The line being sung, under the progress bar. Nothing at all while the track has no synced lyrics.
/// Once it has, the row keeps its height between lines, so the player does not jump at each pause in the song.
struct CurrentLyricView: View {
    static let height: CGFloat = 14

    let store: NowPlayingStore

    var body: some View {
        if store.syncedLyrics != nil {
            // Four times a second is fine-grained enough for lines that last seconds; the clock itself is exact.
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                let text = store.lyric(at: timeline.date)?.text ?? ""
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTokens.primaryText.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: text)
            }
        }
    }
}
