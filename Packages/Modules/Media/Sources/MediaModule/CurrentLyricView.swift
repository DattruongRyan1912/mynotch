import NotchUI
import SwiftUI

/// What the row under the transport controls holds. `reserved` is the row with nothing in it: while a lyrics source
/// is on and the words are still on their way (or the track has none), the player keeps its place.
nonisolated enum LyricRow: Equatable, Sendable {
    case absent, reserved, synced, unsynced
}

/// The line being sung, centred under the transport controls. One dimmed note when lrclib has the words but no
/// timing; nothing at all (not even the row's height) while no lyrics source is on.
/// The row keeps its height between lines, so the player does not jump at each pause in the song.
struct CurrentLyricView: View {
    static let height: CGFloat = 14

    let store: NowPlayingStore

    var body: some View {
        switch store.lyricRow {
        case .absent:
            EmptyView()
        case .reserved:
            Color.clear.frame(height: Self.height)
        case .synced:
            // Four times a second is fine-grained enough for lines that last seconds; the clock itself is exact.
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                let text = store.lyric(at: timeline.date)?.text ?? ""
                row(text)
                    .foregroundStyle(NotchTokens.primaryText.opacity(0.9))
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: text)
            }
        case .unsynced:
            row("Chỉ có lời không đồng bộ")
                .foregroundStyle(NotchTokens.secondaryText.opacity(0.7))
        }
    }

    /// One centred line of fixed height; a long one is cut at its tail.
    private func row(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .center)
    }
}
