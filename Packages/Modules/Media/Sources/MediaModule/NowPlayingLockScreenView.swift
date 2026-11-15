import NotchUI
import SwiftUI

/// What the lock screen's buttons show and do. They are the Media tab's buttons: the same looks (so a skip the player prohibits
/// is faded and does nothing) and the same actions, which take the same route (a Chrome video's skip goes to the YouTube
/// extension, anything else to MediaRemote).
struct LockScreenTransport {
    /// One button of the row, as the view draws it and as a test can press it.
    struct Control: Identifiable {
        enum Kind { case previous, playPause, next }

        var kind: Kind
        var look: MediaControlLook
        var perform: () -> Void
        var id: Kind { kind }
    }

    let store: NowPlayingStore
    let actions: MediaActions

    private var context: MediaControlContext { store.controlContext(hasVolume: false, volumeIsOpen: false) }

    var previous: MediaControlLook { MediaControlButton.previous.look(in: context) }
    var next: MediaControlLook { MediaControlButton.next.look(in: context) }
    /// From the activity's snapshot, which keeps the last track through the empty state between two tracks.
    var isPlaying: Bool { store.activityIsPlaying }

    /// What pressing it will do: the icon of the other state, as the tab's button.
    var playPause: MediaControlLook {
        MediaControlLook(
            symbol: isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Tạm dừng" : "Phát", isEnabled: true, isActive: false
        )
    }

    /// Left to right. The view draws exactly these, each with its own action.
    var controls: [Control] {
        [
            Control(kind: .previous, look: previous, perform: skipBack),
            Control(kind: .playPause, look: playPause, perform: togglePlayPause),
            Control(kind: .next, look: next, perform: skipForward),
        ]
    }

    func togglePlayPause() { actions.send(.togglePlayPause) }
    func skipBack() { actions.press(.previous) }
    func skipForward() { actions.press(.next) }
}

/// Lock screen widget: cover, title, artist and a thin progress bar; while the lock screen allows them, the previous, play/pause and
/// next buttons and, under the track, the lyric line being sung and the next one. It reads the store, so it is offered once and
/// follows the track.
struct NowPlayingLockScreenView: View {
    static let artworkSize: CGFloat = 40
    static let progressHeight: CGFloat = 3

    let transport: LockScreenTransport
    /// The lock screen module's "Điều khiển nhạc trên màn hình khoá". Off, nothing here can be pressed.
    @Environment(\.lockScreenControlsEnabled) private var controlsEnabled
    /// The lock screen module's "Hiện lời bài hát trên màn hình khoá", apart from the controls. Off, no lyric row is made at all.
    @Environment(\.lockScreenLyricsEnabled) private var lyricsEnabled

    private var store: NowPlayingStore { transport.store }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ArtworkView(artwork: store.activityArtwork, icon: store.activityAppIcon, size: Self.artworkSize, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.state.title ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NotchTokens.primaryText)
                        .lineLimit(1)
                    if let artist = store.state.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 11))
                            .foregroundStyle(NotchTokens.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if controlsEnabled {
                    HStack(spacing: 2) {
                        ForEach(transport.controls) { control in
                            RowButton(
                                symbol: control.look.symbol, label: control.look.label,
                                symbolSize: control.kind == .playPause ? 20 : 14, isActive: control.look.isActive,
                                action: control.perform
                            )
                            .disabled(!control.look.isEnabled)
                            .opacity(control.look.isEnabled ? 1 : 0.35)
                        }
                    }
                }
            }
            if lyricsEnabled, store.syncedLyrics?.isEmpty == false {
                LockScreenLyricsView(store: store)
            }
            LockScreenProgress(store: store)
        }
        // The lock screen draws this on a black card of its own, whatever the notch's look is.
        .notchOnDarkBackground()
    }
}

/// How far into the track it is: a thin bar, not seekable. It moves on each whole second of the playback, as the tab's does.
private struct LockScreenProgress: View {
    let store: NowPlayingStore
    @Environment(\.notchAccent) private var accent

    var body: some View {
        TimelineView(PlaybackTickSchedule(anchor: store.state.elapsedAnchor, isPlaying: store.state.isPlaying)) { timeline in
            let progress = PlaybackProgress(state: store.state, at: timeline.date)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(PlaybackProgressView.fill(tint: store.activeTint?.primary, isActive: false, accent: accent))
                        .frame(width: geometry.size.width * progress.fraction)
                }
            }
            .frame(height: NowPlayingLockScreenView.progressHeight)
            .accessibilityElement()
            .accessibilityLabel("Tiến trình")
            .accessibilityValue("\(progress.elapsedText) / \(progress.duration.map(PlaybackProgress.format) ?? "--:--")")
        }
    }
}
