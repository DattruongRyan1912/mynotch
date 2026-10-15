import NotchUI
import SwiftUI

/// The "Media" tab: cover, track, a seekable progress bar and the row of buttons, and under them the lyric line,
/// centred across the tab.
struct MediaTabView: View {
    static let artworkSize: CGFloat = 96
    /// Between the cover and controls and the lyric row under them.
    static let lyricGap: CGFloat = 6
    /// The tab bar's height when there are two or more tabs; `NotchTab.preferredHeight` includes it.
    static let tabBarHeight: CGFloat = 30
    /// The tab's declared height: the player with its lyric row, plus what the notch adds around a tab's content.
    static let preferredHeight = artworkSize + lyricGap + CurrentLyricView.height + NotchTokens.padding + tabBarHeight

    let store: NowPlayingStore
    let actions: MediaActions
    let volume: VolumeModel

    var body: some View {
        Group {
            if let message = store.failureMessage {
                MediaMessage(systemImage: "exclamationmark.triangle", text: message)
            } else if store.state.isActive {
                player
            } else {
                MediaMessage(systemImage: "music.note", text: "Không có gì đang phát")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var player: some View {
        // The lyric row is its own row at the bottom, across the whole tab, so the cover and the controls above it
        // stay where they are whether it holds a line, the note or nothing.
        VStack(spacing: Self.lyricGap) {
            coverAndControls
            CurrentLyricView(store: store, togglePanel: actions.toggleLyricsPanel)
        }
    }

    private var coverAndControls: some View {
        HStack(spacing: 14) {
            ArtworkView(artwork: store.artworkImage, icon: store.appIcon, size: Self.artworkSize, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(store.state.title ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NotchTokens.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    // Takes its width first, so a long title truncates instead of the app name.
                    PlayerBadge(store: store)
                        .layoutPriority(1)
                }
                Text(store.state.artist ?? store.state.album ?? " ")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                PlaybackProgressView(store: store, seek: actions.seek)
                Spacer(minLength: 2)
                MediaControlsRow(store: store, actions: actions, volume: volume)
            }
            // The cover's height. Not stretched to the space available, which would pull the column out of line
            // with the cover.
            .frame(minHeight: Self.artworkSize)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Progress bar plus elapsed and remaining time. Dragging (or clicking) seeks once, on release:
/// the adapter runs one perl process per command, so seeking on every drag step would only queue work.
struct PlaybackProgressView: View {
    let store: NowPlayingStore
    let seek: (Double) -> Void
    @Environment(\.notch) private var notch
    @State private var dragFraction: Double?
    @State private var pendingSeek: PendingSeek?
    @State private var isHovering = false

    var body: some View {
        TimelineView(PlaybackTickSchedule(anchor: store.state.elapsedAnchor, isPlaying: store.state.isPlaying)) { timeline in
            let progress = PlaybackProgress(
                state: store.state, at: timeline.date, dragFraction: dragFraction, pendingSeek: pendingSeek
            )
            VStack(spacing: 2) {
                bar(progress)
                HStack {
                    Text(progress.elapsedText)
                    Spacer()
                    Text(progress.remainingText)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTokens.secondaryText)
            }
        }
        // The notch stays open while the pointer is outside it during a drag; never leave it held open.
        .onDisappear { if dragFraction != nil { notch.setDragging(false) } }
    }

    private func bar(_ progress: PlaybackProgress) -> some View {
        let canSeek = progress.duration != nil
        let isActive = canSeek && (dragFraction != nil || isHovering)
        return GeometryReader { geometry in
            let width = geometry.size.width
            let filled = width * progress.fraction
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(isActive ? NotchTokens.accent : NotchTokens.primaryText.opacity(0.85))
                    .frame(width: filled)
                if isActive {
                    Circle()
                        .fill(NotchTokens.primaryText)
                        .frame(width: 10, height: 10)
                        .offset(x: min(max(filled - 5, 0), max(width - 10, 0)))
                        .transition(.opacity)
                }
            }
            .frame(height: isActive ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(seekGesture(width: width, progress: progress), isEnabled: canSeek)
        }
        .frame(height: 10)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isActive)
        .accessibilityElement()
        .accessibilityLabel("Tiến trình")
        .accessibilityValue("\(progress.elapsedText) / \(progress.duration.map(PlaybackProgress.format) ?? "--:--")")
    }

    private func seekGesture(width: CGFloat, progress: PlaybackProgress) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragFraction == nil { notch.setDragging(true) }
                dragFraction = Self.fraction(of: value.location.x, in: width)
            }
            .onEnded { value in
                dragFraction = nil
                notch.setDragging(false)
                guard let seconds = progress.seconds(atFraction: Self.fraction(of: value.location.x, in: width)) else { return }
                pendingSeek = PendingSeek(seconds: seconds, anchor: store.state.elapsedAnchor, date: .now)
                seek(seconds)
            }
    }

    private static func fraction(of x: CGFloat, in width: CGFloat) -> Double {
        width > 0 ? min(max(Double(x / width), 0), 1) : 0
    }
}

/// The playing app's icon and name; browsers show the browser, not their media helper.
private struct PlayerBadge: View {
    let store: NowPlayingStore

    var body: some View {
        if let name = store.appName {
            HStack(spacing: 4) {
                if let icon = store.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                }
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
                    .fixedSize()
            }
            .help(name)
        }
    }
}

private struct MediaMessage: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(NotchTokens.secondaryText)
    }
}
