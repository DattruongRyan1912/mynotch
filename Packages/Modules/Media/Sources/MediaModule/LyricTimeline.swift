import NotchUI
import SwiftUI

/// The timeline of the lyric views: it ticks when the position reaches a line (see `LyricTickSchedule`), since a line is all that
/// changes in them: the fill within a line is no business of the timeline's. That is about one evaluation of the views per line
/// where the four ticks a second of before were eight times as many for a song with a line every two seconds. It stands still
/// while the notch or the panel cannot be seen, showing what it showed when it left the screen, and while the song is paused.
struct LyricTimeline<Content: View>: View {
    @Environment(\.notchIsOnScreen) private var isOnScreen
    let store: NowPlayingStore
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if isOnScreen {
            // Read here, so that a seek or a pause, which move the lines' times on the clock, make a new schedule.
            TimelineView(LyricTickSchedule(
                anchor: store.state.elapsedAnchor, isPlaying: store.state.isPlaying, lineTimes: store.syncedLyrics?.map(\.time) ?? []
            )) { content($0.date) }
        } else {
            content(.now)
        }
    }
}
