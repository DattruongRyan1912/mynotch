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

/// Bars that move while music plays and rest while it is paused: right side of the closed notch, and in the tab.
/// They show the real spectrum while the system audio tap delivers it, and a made-up motion otherwise.
/// They animate inside the view from `store`, so the activity is never re-published per frame.
struct NowPlayingBars: View {
    nonisolated static let barCount = 4
    static let barWidth: CGFloat = 3
    static let minHeight: CGFloat = 3
    static let maxHeight: CGFloat = 14

    let store: NowPlayingStore

    var body: some View {
        // Only these properties: the body must not re-run for every position update of `store.state`.
        // The bands change about 30 times a second while the tap runs, which is when the bars must redraw anyway.
        let isPlaying = store.activityIsPlaying
        let spectrum = store.spectrumBands
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || spectrum != nil)) { timeline in
            let levels = Self.levels(spectrum: spectrum, isPlaying: isPlaying, at: timeline.date)
            HStack(spacing: 2) {
                ForEach(levels.indices, id: \.self) { bar in
                    Capsule()
                        .fill(NotchTokens.accent)
                        .frame(width: Self.barWidth, height: Self.minHeight + (Self.maxHeight - Self.minHeight) * levels[bar])
                }
            }
            .frame(height: Self.maxHeight)
            .animation(.easeOut(duration: 0.3), value: isPlaying)
        }
        .accessibilityHidden(true)
        // Lets the module run the tap only while some bars are on screen.
        .onAppear { store.spectrumViewAppeared() }
        .onDisappear { store.spectrumViewDisappeared() }
    }

    /// One level in 0…1 per bar: the tap's bands while there are some, the made-up motion otherwise, 0 while paused.
    nonisolated static func levels(spectrum: [Float]?, isPlaying: Bool, at date: Date) -> [Double] {
        (0..<barCount).map { bar in
            guard isPlaying else { return 0 }
            guard let spectrum else { return level(bar: bar, at: date) }
            return bar < spectrum.count ? min(max(Double(spectrum[bar]), 0), 1) : 0
        }
    }

    /// A made-up level in 0…1: two out-of-step waves per bar so the motion never visibly repeats.
    nonisolated static func level(bar: Int, at date: Date) -> Double {
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
        let offset = Double(bar)
        let beat = 0.5 + 0.5 * sin(time * (6.3 + offset * 1.7) + offset * 1.9)
        let swell = 0.5 + 0.5 * sin(time * (2.1 + offset * 0.8) + offset * 2.7)
        return 0.2 + 0.8 * beat * (0.45 + 0.55 * swell)
    }
}
