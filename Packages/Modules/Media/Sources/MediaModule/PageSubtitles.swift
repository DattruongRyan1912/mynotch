import Foundation
import MyNotchCore
import SwiftUI
import YouTubeBridgeKit

/// The film's subtitles drawn in its own page instead of a window over the screen: the line on the film now is sent to the tab, which
/// draws it on its player, so it goes with the tab when the user changes tab or app, and is inside the player when it is fullscreen.
/// A line is sent when it changes and again every `heartbeat` while it stands, each with how long it may stay (`until`): the page
/// takes it away by itself when nothing comes, so an app that quits never leaves one behind.
final class PageSubtitles {
    /// A line that stands (a pause, a long one) is said again this often.
    static let heartbeat: TimeInterval = 4
    /// How long a line said by the heartbeat may stay: past the next heartbeat, so it does not blink.
    static let lifetime: TimeInterval = 8
    /// A line stays this much past the moment the next one is due, so the next one replaces it rather than a gap.
    static let overlap: TimeInterval = 0.3

    /// Where and how large the user put the floating subtitles: the share of the video's height under them, and the factor of the size.
    var gap = FullscreenSubtitleRule.bottomGap
    var scale = 1.0

    private let store: NowPlayingStore
    private let scheduler: any Scheduler
    private let now: () -> Date
    /// Writes the line to the Chrome the tab is in; false when it could not.
    private let send: (TabSubtitle, Int) -> Bool
    private(set) var target: TabRef?
    private var timer: ScheduledAction?
    private var signature: Signature?

    private struct Signature: Equatable {
        var anchor: PlaybackAnchor?
        var isPlaying: Bool
        var lineTimes: [Double]
        var gap: Double
        var scale: Double
    }

    init(store: NowPlayingStore, scheduler: any Scheduler, now: @escaping () -> Date = Date.init, send: @escaping (TabSubtitle, Int) -> Bool) {
        self.store = store
        self.scheduler = scheduler
        self.now = now
        self.send = send
    }

    /// Draws the subtitles in `target`'s page, or in none. Safe to call with every update of the track: a line goes out only when the
    /// tab, the lines or where the film is on the clock changed.
    func update(target: TabRef?) {
        if target != self.target {
            if let old = self.target { _ = send(TabSubtitle(tab: old.tab, text: "", until: 0, gap: gap, scale: scale), old.connection) }
            self.target = target
            signature = nil
        }
        guard target != nil else {
            timer?.cancel()
            timer = nil
            return
        }
        let current = Signature(
            anchor: store.state.elapsedAnchor, isPlaying: store.state.isPlaying, lineTimes: store.syncedLyrics?.map(\.time) ?? [],
            gap: gap, scale: scale
        )
        guard current != signature else { return }
        signature = current
        tick()
    }

    /// The line on the film now, then the next look: when the next line is due, or at the heartbeat.
    private func tick() {
        timer?.cancel()
        timer = nil
        guard let target else { return }
        let date = now()
        let next = nextLine(after: date).map { $0.timeIntervalSince(date) }
        let until = next.map { min($0 + Self.overlap, Self.lifetime) } ?? Self.lifetime
        _ = send(TabSubtitle(tab: target.tab, text: store.subtitle(at: date), until: until, gap: gap, scale: scale), target.connection)
        let wait = min(next ?? Self.heartbeat, Self.heartbeat)
        timer = scheduler.schedule(after: .milliseconds(Int64((max(wait, 0.02) * 1000).rounded(.up)))) { [weak self] in self?.tick() }
    }

    /// When the film reaches its next line after `date`; nil while it stands still or has no line after.
    private func nextLine(after date: Date) -> Date? {
        var entries = LyricTimeline<EmptyView>.schedule(for: store).entries(from: date, mode: .normal)
        _ = entries.next()
        return entries.next()
    }
}
