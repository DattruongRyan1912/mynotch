import Foundation
import NotchUI
import SwiftUI

/// Left side of the closed notch: small cover art. Reads the store's activity snapshot, which keeps the
/// last track's cover through the empty state between two tracks.
struct NowPlayingActivityArtwork: View {
    let store: NowPlayingStore

    var body: some View {
        ArtworkView(artwork: store.activityArtwork, icon: store.activityAppIcon, size: 16, cornerRadius: 4)
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
        // Only this property: the body must not re-run for every position update of `store.state`.
        let isPlaying = store.activityIsPlaying
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { timeline in
            HStack(spacing: 2) {
                ForEach(0..<Self.barCount, id: \.self) { bar in
                    let level = isPlaying ? Self.level(bar: bar, at: timeline.date) : 0
                    Capsule()
                        .fill(NotchTokens.accent)
                        .frame(width: Self.barWidth, height: Self.minHeight + (Self.maxHeight - Self.minHeight) * level)
                }
            }
            .frame(height: Self.maxHeight)
            .animation(.easeOut(duration: 0.3), value: isPlaying)
        }
        .accessibilityHidden(true)
    }

    /// A made-up level in 0…1: two out-of-step waves per bar so the motion never visibly repeats.
    /// M5 replaces it with the real spectrum when that setting is on.
    nonisolated static func level(bar: Int, at date: Date) -> Double {
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
        let offset = Double(bar)
        let beat = 0.5 + 0.5 * sin(time * (6.3 + offset * 1.7) + offset * 1.9)
        let swell = 0.5 + 0.5 * sin(time * (2.1 + offset * 0.8) + offset * 2.7)
        return 0.2 + 0.8 * beat * (0.45 + 0.55 * swell)
    }
}
