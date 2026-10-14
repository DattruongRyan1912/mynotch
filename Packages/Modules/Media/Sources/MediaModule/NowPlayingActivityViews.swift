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
            let _ = NotchPerf.count(.spectrumUpdates)
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

/// Under the closed notch while the lyrics are synced: the line being sung and the one coming next, like karaoke.
/// Two rows of one line each, so the strip keeps its height whatever the lyrics say. The notch gives it its width
/// and its side padding. While the strip is held across a track change and the new lyrics are not there yet, it shows
/// the dimmed note alone, so the notch keeps its height.
struct NowPlayingLyricStrip: View {
    static let height: CGFloat = 36

    let store: NowPlayingStore

    var body: some View {
        // Four times a second is fine-grained enough for lines that last seconds; the clock itself is exact.
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            // The note alone while the lyrics are gone and the new ones are not there yet (between two tracks).
            let strip = store.lyricStrip(at: timeline.date) ?? .waiting
            ZStack {
                rows(strip)
                    // A new pair of lines slides up into place while the old one leaves.
                    .id(strip)
                    .transition(.asymmetric(
                        insertion: .offset(y: 6).combined(with: .opacity),
                        removal: .offset(y: -6).combined(with: .opacity)
                    ))
            }
            .animation(.easeOut(duration: 0.2), value: strip)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
            .clipped()
        }
    }

    private func rows(_ strip: LyricStrip) -> some View {
        VStack(spacing: 2) {
            Text(strip.current ?? LyricStrip.note)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(strip.current == nil ? NotchTokens.secondaryText : NotchTokens.primaryText)
                .frame(height: 16)
            Text(strip.next ?? "")
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
                .frame(height: 14)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
        // One element that reads the lines, never the note.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lời bài hát")
        .accessibilityValue(strip.spoken)
    }
}
