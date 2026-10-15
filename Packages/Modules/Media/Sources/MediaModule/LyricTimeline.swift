import NotchUI
import SwiftUI

/// The timeline of the lyric views. While the lines are filled word by word it ticks when a line begins (see
/// `LyricTickSchedule`); the fill itself is no business of the timeline's. Otherwise it is the four ticks a second the lyric
/// rows always had. Either way it stands still while the notch is hidden, showing what it showed when it left the screen.
struct LyricTimeline<Content: View>: View {
    @Environment(\.notchIsOnScreen) private var isOnScreen
    let store: NowPlayingStore
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if store.karaokeIsActive {
            // Read here, so that a seek or a pause, which move the lines' times on the clock, make a new schedule.
            let schedule = LyricTickSchedule(
                anchor: store.state.elapsedAnchor, isPlaying: store.state.isPlaying, lineTimes: store.syncedLyrics?.map(\.time) ?? []
            )
            if isOnScreen {
                TimelineView(schedule) { content($0.date) }
            } else {
                content(.now)
            }
        } else {
            NotchTimeline(every: 0.25, content: content)
        }
    }
}
