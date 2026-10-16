import AppKit
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
/// They are drawn in layers and moved straight from `store` (see `SpectrumBars`), so the activity is never re-published
/// per frame and SwiftUI never redraws the notch for them.
struct NowPlayingBars: View {
    nonisolated static let barCount = 4
    static let barWidth: CGFloat = 3
    static let spacing: CGFloat = 2
    static let minHeight: CGFloat = 3
    static let maxHeight: CGFloat = 14
    /// Every bar side by side, as tall as the tallest one can get.
    static let size = CGSize(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing, height: maxHeight)

    let store: NowPlayingStore

    var body: some View {
        SpectrumBars(store: store)
            .frame(width: Self.size.width, height: Self.size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

    /// How tall a bar is at `level`.
    static func height(forLevel level: Double) -> CGFloat {
        minHeight + (maxHeight - minHeight) * level
    }

    /// How long the made-up motion takes to come back to where it was: every wave of every bar runs at a whole multiple of
    /// 0.1 rad/s, so the motion repeats exactly every 2π / 0.1 s (about 63 s) and a loop of that length has no seam.
    nonisolated static let madeUpLoop: TimeInterval = 2 * .pi / 0.1
    /// Keyframes per second of the loop: the 30 steps a second the bars always made.
    nonisolated static let madeUpRate = 30.0
    /// Keyframes in a loop; each is held for `madeUpLoop / madeUpKeyframeCount`, a hair over a thirtieth of a second.
    nonisolated static let madeUpKeyframeCount = Int((madeUpLoop * madeUpRate).rounded())

    /// How far into the loop `date` is. It follows the wall clock, so every bars view on every display shows the same height at
    /// the same moment, and one that joins later picks up where the others are.
    nonisolated static func madeUpPhase(at date: Date) -> TimeInterval {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: madeUpLoop)
    }

    /// The heights, in points, that bar `bar` takes over one loop of the made-up motion, one per keyframe: what `level(bar:at:)`
    /// says at the start of each.
    static func madeUpHeights(bar: Int) -> [CGFloat] {
        let step = madeUpLoop / Double(madeUpKeyframeCount)
        return (0..<madeUpKeyframeCount).map { height(forLevel: level(bar: bar, at: Date(timeIntervalSinceReferenceDate: Double($0) * step))) }
    }

    /// How many times `madeUpKeyframes` was built, for tests: once for the whole run of the app.
    private(set) static var madeUpKeyframeBuilds = 0

    /// `madeUpHeights` of every bar, as Core Animation takes them. Built the first time the made-up motion is shown and kept: building
    /// them takes a few milliseconds, which would otherwise land on every attach of every display (each collapse and each open of the
    /// Media tab) for the price of a quarter of a megabyte.
    static let madeUpKeyframes: [[NSNumber]] = {
        madeUpKeyframeBuilds += 1
        return (0..<barCount).map { madeUpHeights(bar: $0).map { NSNumber(value: Double($0)) } }
    }()
}

/// Under the closed notch while the lyrics are synced: the line being sung and the one coming next, like karaoke.
/// Two rows of one line each, so the strip keeps its height whatever the lyrics say. The notch gives it its width
/// and its side padding. While the strip is held across a track change and the new lyrics are not there yet, it shows
/// the dimmed note alone, so the notch keeps its height.
struct NowPlayingLyricStrip: View {
    static let height: CGFloat = 36
    /// The fonts of the two rows: the strip draws them and measures its width in them, so the two cannot drift apart.
    static let currentFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let nextFont = NSFont.systemFont(ofSize: 11)
    /// A line that is still wider than the notch can be gets this much smaller before it is cut off.
    static let minimumScale: CGFloat = 0.8

    let store: NowPlayingStore
    @Environment(\.notchSurface) private var surface

    var body: some View {
        // At each line (see `LyricTickSchedule`), which is when the text changes: a line that is filled word by word is one
        // animation the render server runs, and nothing else here moves. Not at all while the notch is hidden.
        // The style is read here, in the body: the timeline's closure runs later, where the environment is not this view's to read.
        let karaoke: KaraokeStyle = surface.isLiquidGlass ? .stripOnGlass : .strip
        LyricTimeline(store: store) { date in
            // The note alone while the lyrics are gone and the new ones are not there yet (between two tracks).
            let strip = store.lyricStrip(at: date) ?? .waiting
            ZStack {
                rows(strip, line: store.lyric(at: date), karaoke: karaoke)
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
            // The notch is as wide as the wider of the two rows, so the whole line shows; it changes once per line.
            .notchStripWidth(strip.preferredWidth())
        }
    }

    private func rows(_ strip: LyricStrip, line: LyricLine?, karaoke: KaraokeStyle) -> some View {
        VStack(spacing: 2) {
            if store.karaokeIsActive, let line, strip.current != nil, line.words != nil {
                KaraokeLine(line: line, store: store, style: karaoke)
                    .frame(height: 16)
            } else {
                Text(strip.current ?? LyricStrip.note)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(strip.current == nil ? NotchTokens.secondaryText : NotchTokens.primaryText)
                    .minimumScaleFactor(Self.minimumScale)
                    .frame(height: 16)
            }
            Text(strip.next ?? "")
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
                .minimumScaleFactor(Self.minimumScale)
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

extension KaraokeStyle {
    /// The current line of the strip under the notch: the size and weight of its text row, the sung part lit. White, as the black
    /// notch's text always was: a colour in a layer is made once, so it cannot be a token that follows the look.
    static let strip = KaraokeStyle(fontSize: 12, weight: .semibold, lit: NSColor(Color.white), dim: NSColor(Color.white.opacity(0.6)))
    /// The same strip on Liquid Glass: the system's label colours, which turn dark on light glass.
    static let stripOnGlass = KaraokeStyle(fontSize: 12, weight: .semibold, lit: .labelColor, dim: .secondaryLabelColor)
}
