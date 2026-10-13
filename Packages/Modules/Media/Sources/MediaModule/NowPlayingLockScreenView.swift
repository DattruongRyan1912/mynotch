import NotchUI
import SwiftUI

/// Lock screen widget: cover, title, artist and whether it plays. It reads the store, so it is offered once and follows the track.
struct NowPlayingLockScreenView: View {
    let store: NowPlayingStore

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: store.activityArtwork, icon: store.activityAppIcon, size: 40, cornerRadius: 8)
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
            Image(systemName: store.activityIsPlaying ? "play.fill" : "pause.fill")
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.secondaryText)
        }
    }
}
