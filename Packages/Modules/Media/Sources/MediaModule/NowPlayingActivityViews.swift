import Foundation
import NotchUI
import SwiftUI

/// Left side of the closed notch: small cover art.
struct NowPlayingActivityArtwork: View {
    let store: NowPlayingStore

    var body: some View {
        ArtworkView(store: store, size: 16, cornerRadius: 4)
    }
}

/// Right side of the closed notch: bars that move while music plays and rest while it is paused.
/// They animate inside the view from `store`, so the activity is never re-published per frame.
struct NowPlayingBars: View {
    nonisolated static let barCount = 4
    static let barWidth: CGFloat = 3
    static let minHeight: CGFloat = 3
    static let maxHeight: CGFloat = 14

    let store: NowPlayingStore

    var body: some View {
        let isPlaying = store.state.isPlaying
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { timeline in
            let levels = isPlaying ? Self.levels(at: timeline.date) : Array(repeating: 0, count: Self.barCount)
            HStack(spacing: 2) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(NotchTokens.accent)
                        .frame(width: Self.barWidth, height: Self.minHeight + (Self.maxHeight - Self.minHeight) * levels[index])
                }
            }
            .frame(height: Self.maxHeight)
            .animation(.easeOut(duration: 0.3), value: isPlaying)
        }
        .accessibilityHidden(true)
    }

    /// Made-up levels in 0…1: two out-of-step waves per bar so the motion never visibly repeats.
    /// M5 replaces them with the real spectrum when that setting is on.
    nonisolated static func levels(at date: Date) -> [Double] {
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
        return (0..<barCount).map { bar in
            let offset = Double(bar)
            let beat = 0.5 + 0.5 * sin(time * (6.3 + offset * 1.7) + offset * 1.9)
            let swell = 0.5 + 0.5 * sin(time * (2.1 + offset * 0.8) + offset * 2.7)
            return 0.2 + 0.8 * beat * (0.45 + 0.55 * swell)
        }
    }
}
