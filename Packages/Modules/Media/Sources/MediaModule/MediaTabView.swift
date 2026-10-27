import MyNotchCore
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

    // With two sources or more the chips take a row above the player, and so does the EQ control while the Âm thanh module runs
    // (at the end of the same row, alone in it when there are no chips); the tab's height does not change: what they take is taken
    // from the player. Without a lyric row the player is as tall as before, less nothing (the row and its gap are the lyric row's
    // room); with one it is a smaller cover beside a column of one line less.
    static let chipGap: CGFloat = 2
    /// The cover while the row above it (the chips, the EQ control) and the lyric row are both there.
    static let compactArtworkSize: CGFloat = artworkSize - 18
    static let compactLyricGap: CGFloat = 4

    let store: NowPlayingStore
    let actions: MediaActions
    let volume: VolumeModel
    /// The sources, for the chips; nil is a tab with one source, as it always was.
    var sources: MediaSourceModel?
    /// What the player shows while the user has chosen a source other than the primary one.
    var displayStore: NowPlayingStore?
    /// What the EQ control switches; nil is a tab with none, as it always was.
    var equalizer: EqualizerState?
    /// The subtitles of what plays; nil is a tab without the control.
    var subtitles: SubtitleControls?

    init(
        store: NowPlayingStore, actions: MediaActions, volume: VolumeModel, sources: MediaSourceModel? = nil,
        displayStore: NowPlayingStore? = nil, icons: PlayerAppCache = PlayerAppCache(), equalizer: EqualizerState? = nil,
        subtitles: SubtitleControls? = nil
    ) {
        self.store = store
        self.actions = actions
        self.volume = volume
        self.sources = sources
        self.displayStore = displayStore
        self.equalizer = equalizer
        self.subtitles = subtitles
        _icons = State(initialValue: icons)
    }

    /// What the player draws: the primary source's store, or the other source's while the user looks at that.
    private var shown: NowPlayingStore {
        (sources?.displayIsPrimary ?? true) ? store : (displayStore ?? store)
    }

    /// Whether the chips are up: there are sources to choose between.
    private var hasChips: Bool { sources?.showsChips ?? false }

    /// Whether the row above the player is up: the chips, the subtitles, the EQ control, or some of them.
    private var hasSourceRow: Bool { hasChips || hasSubtitleControl || EQQuickControl.isShown(equalizer) }

    /// Subtitles are the primary source's, as lyrics are: the control is not there while the player shows another source.
    private var hasSubtitleControl: Bool {
        (sources?.displayIsPrimary ?? true) && SubtitleQuickControl.isShown(subtitles, for: store.state)
    }

    @State private var isAppeared = false
    @Environment(\.notchIsOnScreen) private var isOnScreen
    /// The apps' icons for the chips, looked up once for as long as the tab lives: LaunchServices is too slow for every redraw.
    @State private var icons: PlayerAppCache

    var body: some View {
        Group {
            if let message = store.failureMessage {
                MediaMessage(systemImage: "exclamationmark.triangle", text: message)
            } else if shown.state.isActive {
                player
            } else {
                MediaMessage(systemImage: "music.note", text: "Không có gì đang phát")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The apps are read only while this is on screen: a tab that is not mounted, or a notch that cannot be seen, costs nothing.
        .onAppear {
            isAppeared = true
            sources?.setTabVisible(isOnScreen)
        }
        .onDisappear {
            isAppeared = false
            sources?.setTabVisible(false)
        }
        .onChange(of: isOnScreen) { _, isOnScreen in sources?.setTabVisible(isAppeared && isOnScreen) }
    }

    private var player: some View {
        // The lyric row is its own row at the bottom, across the whole tab, so the cover and the controls above it
        // stay where they are whether it holds a line, the note or nothing.
        let hasLyricRow = shown.lyricRow != .absent
        let compact = hasSourceRow && hasLyricRow
        return VStack(spacing: 0) {
            if hasSourceRow {
                sourceRow
                    .padding(.bottom, Self.chipGap)
            }
            coverAndControls(compact: compact)
            // The row's place is kept, but only the primary source has lyrics to put in it: its words, bars and tint.
            CurrentLyricView(store: shown, togglePanel: actions.toggleLyricsPanel)
                .padding(.top, hasLyricRow ? (compact ? Self.compactLyricGap : Self.lyricGap) : 0)
        }
        // The cover's colours as a faint glow; a background, so it never changes the size the tab asks for.
        .background { ArtworkGlow(tint: shown.activeTint) }
    }

    /// The chips, which scroll in the room the EQ control leaves, and the control at the end of the row.
    private var sourceRow: some View {
        HStack(spacing: 0) {
            if let sources, hasChips {
                MediaSourceChipsView(model: sources, icons: icons)
            } else {
                Spacer(minLength: 0)
            }
            if hasSubtitleControl {
                SubtitleQuickControl(controls: subtitles, state: store.state)
            }
            EQQuickControl(equalizer: equalizer)
        }
        .frame(height: MediaSourceChipsView.height)
    }

    private func coverAndControls(compact: Bool) -> some View {
        let size = compact ? Self.compactArtworkSize : Self.artworkSize
        return HStack(spacing: 14) {
            Button(action: actions.openPlayer) {
                ArtworkView(artwork: shown.artworkImage, icon: shown.appIcon, size: size, cornerRadius: compact ? 10 : 12)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Mở \(shown.appName ?? "ứng dụng đang phát")")
            .accessibilityAddTraits(.isButton)
            .help("Mở \(shown.appName ?? "ứng dụng đang phát")")
            VStack(alignment: .leading, spacing: 0) {
                if compact {
                    // One line for what two lines said, and no badge: the chips say which app it is. With no chips (only the EQ
                    // control above) nothing does, so the badge stays at the end of the line.
                    if hasChips {
                        Button(action: actions.openPlayer) {
                            compactTitle
                        }
                        .buttonStyle(.plain)
                        .help("Mở \(shown.appName ?? "ứng dụng đang phát")")
                    } else {
                        HStack(spacing: 8) {
                            Button(action: actions.openPlayer) {
                                compactTitle
                            }
                            .buttonStyle(.plain)
                            .help("Mở \(shown.appName ?? "ứng dụng đang phát")")
                            Spacer(minLength: 0)
                            PlayerBadge(store: shown, open: actions.openPlayer)
                                .layoutPriority(1)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button(action: actions.openPlayer) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(shown.state.title ?? "")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(NotchTokens.primaryText)
                                    .lineLimit(1)
                                Text(shown.state.artist ?? shown.state.album ?? " ")
                                    .font(.system(size: 12))
                                    .foregroundStyle(NotchTokens.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Mở \(shown.appName ?? "ứng dụng đang phát")")
                        Spacer(minLength: 0)
                        // Takes its width first, so a long title truncates instead of the app name.
                        PlayerBadge(store: shown, open: actions.openPlayer)
                            .layoutPriority(1)
                    }
                }
                Spacer(minLength: compact ? 2 : 4)
                PlaybackProgressView(store: shown, seek: actions.seek)
                Spacer(minLength: 2)
                // The bars show the system's sound, so they stay with the store the notch follows.
                MediaControlsRow(store: shown, actions: actions, volume: volume, barsStore: store)
            }
            // The cover's height. Not stretched to the space available, which would pull the column out of line
            // with the cover.
            .frame(minHeight: size)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var compactTitle: some View {
        Text("\(Text(shown.state.title ?? "").font(.system(size: 14, weight: .semibold)).foregroundStyle(NotchTokens.primaryText))\(Text(subtitle.isEmpty ? "" : "  ·  " + subtitle).font(.system(size: 12)).foregroundStyle(NotchTokens.secondaryText))")
            .lineLimit(1)
    }

    private var subtitle: String { shown.state.artist ?? shown.state.album ?? "" }
}

/// Progress bar plus elapsed and remaining time. Dragging (or clicking) seeks once, on release:
/// the adapter runs one perl process per command, so seeking on every drag step would only queue work.
struct PlaybackProgressView: View {
    let store: NowPlayingStore
    let seek: (Double) -> Void
    @Environment(\.notch) private var notch
    @Environment(\.notchAccent) private var accent
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
                Capsule().fill(NotchTokens.fill(0.18))
                Capsule()
                    .fill(Self.fill(tint: store.activeTint?.primary, isActive: isActive, accent: accent))
                    .animation(.easeInOut(duration: 0.4), value: store.activeTint?.primary)
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

    /// The filled part of the bar: the cover's colour while there is one, else white, and the accent while the pointer is on it.
    static func fill(tint: SRGBColor?, isActive: Bool, accent: Color) -> Color {
        if let tint { return tint.color }
        return isActive ? accent : NotchTokens.primaryText.opacity(0.85)
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
    var open: (() -> Void)? = nil

    var body: some View {
        if let name = store.appName {
            Button(action: { open?() }) {
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
            }
            .buttonStyle(.plain)
            .help(open != nil ? "Mở \(name)" : name)
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
