import NotchUI
import SwiftUI

/// What the lock screen's buttons show and do. They are the Media tab's buttons: the same looks (so a skip the player prohibits
/// is faded and does nothing) and the same actions, which take the same route (a Chrome video's skip goes to the YouTube
/// extension, anything else to MediaRemote).
struct LockScreenTransport {
    let store: NowPlayingStore
    let actions: MediaActions

    private var context: MediaControlContext { store.controlContext(hasVolume: false, volumeIsOpen: false) }

    var previous: MediaControlLook { MediaControlButton.previous.look(in: context) }
    var next: MediaControlLook { MediaControlButton.next.look(in: context) }
    /// From the activity's snapshot, which keeps the last track through the empty state between two tracks.
    var isPlaying: Bool { store.activityIsPlaying }

    func togglePlayPause() { actions.send(.togglePlayPause) }
    func skipBack() { actions.press(.previous) }
    func skipForward() { actions.press(.next) }
}

/// Lock screen widget: cover, title, artist, the previous, play/pause and next buttons, and a thin progress bar under them. It reads
/// the store, so it is offered once and follows the track.
struct NowPlayingLockScreenView: View {
    static let artworkSize: CGFloat = 40
    static let progressHeight: CGFloat = 3

    let transport: LockScreenTransport

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
                HStack(spacing: 2) {
                    ControlButton(look: transport.previous, action: transport.skipBack)
                    PlayPauseButton(isPlaying: transport.isPlaying, action: transport.togglePlayPause)
                    ControlButton(look: transport.next, action: transport.skipForward)
                }
            }
            LockScreenProgress(store: store)
        }
    }
}

/// How far into the track it is: a thin bar, not seekable. It moves on each whole second of the playback, as the tab's does.
private struct LockScreenProgress: View {
    let store: NowPlayingStore

    var body: some View {
        TimelineView(PlaybackTickSchedule(anchor: store.state.elapsedAnchor, isPlaying: store.state.isPlaying)) { timeline in
            let progress = PlaybackProgress(state: store.state, at: timeline.date)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(PlaybackProgressView.fill(tint: store.activeTint?.primary, isActive: false))
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
