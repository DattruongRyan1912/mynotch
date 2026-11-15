import Foundation
import MyNotchCore

/// What the bars are told to show.
nonisolated enum BarsFrame: Equatable {
    /// One level in 0…1 per bar, and whether to ease to it instead of jumping.
    case levels([Double], animated: Bool)
    /// The made-up motion: the bars run it themselves, as an animation the render server plays (see `SpectrumBarsView`).
    case madeUp
}

/// Decides what the bars show and when it is drawn, so the bars' views only draw what they are handed. One driver serves every
/// bars view of a store, whatever the number of displays (see `SpectrumBarsHub`). The bars draw only while they are on screen with
/// something playing. New bands from the tap draw the moment they arrive, with no timer: the tap delivers about 30 sets a second,
/// and a source faster than that is thinned to at most 40 draws a second. The made-up motion is not drawn at all: it is one
/// `.madeUp` frame, and no timer. Time comes from the scheduler and `now`, so tests move it by hand.
final class BarsDriver {
    private static let intervalSeconds: TimeInterval = 0.033_333_333
    /// The least time between two draws of tap bands. The tap's timer has 5 ms of leeway, so its sets come 28 to 38 ms apart;
    /// holding back the early ones for a full interval cost a `Task.sleep` and a main-actor hop each and drifted the rate to
    /// 28 a second. A quarter of an interval short is drawn on arrival; a set that comes sooner waits only until the gap has passed.
    private static let minimumGap: TimeInterval = intervalSeconds * 0.75

    private let scheduler: any Scheduler
    private let now: () -> Date
    private let draw: (BarsFrame) -> Void
    private var isOnScreen = false
    private var isPlaying = false
    private var spectrum: [Float]?
    private var lastLevels: [Double]?
    private var lastDraw: Date?
    /// A set of bands that arrived less than `minimumGap` after the last draw; it draws the latest bands when the gap has passed.
    private var pending: ScheduledAction?

    init(scheduler: any Scheduler, now: @escaping () -> Date = Date.init, draw: @escaping (BarsFrame) -> Void) {
        self.scheduler = scheduler
        self.now = now
        self.draw = draw
    }

    /// What the bars show now, for a view that joins while the others are running.
    var current: BarsFrame {
        if isPlaying && spectrum == nil { return .madeUp }
        return .levels(lastLevels ?? NowPlayingBars.levels(spectrum: spectrum, isPlaying: isPlaying, at: now()), animated: false)
    }

    /// Off screen nothing is drawn or scheduled; back on screen the bars draw their current state at once.
    func setOnScreen(_ onScreen: Bool) {
        guard onScreen != isOnScreen else { return }
        isOnScreen = onScreen
        restart(animated: false)
    }

    /// Pausing eases the bars to rest; playing moves them again at once.
    func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        restart(animated: !playing)
    }

    /// The tap's latest bands, or nil once it stopped, which brings the made-up motion back.
    func setSpectrum(_ bands: [Float]?) {
        guard bands != spectrum else { return }
        spectrum = bands
        guard isOnScreen, isPlaying else { return }
        if bands == nil {
            restart(animated: false)
        } else {
            requestDraw()
        }
    }

    private func restart(animated: Bool) {
        cancelPending()
        guard isOnScreen else { return }
        if isPlaying && spectrum == nil {
            // Once: the bars animate themselves from here, and nothing is drawn or scheduled per frame.
            lastLevels = nil
            draw(.madeUp)
        } else {
            drawNow(animated: animated)
        }
    }

    /// Draws now, or as soon as the gap after the last draw has passed when the set came too soon. The wait ends at the gap, not
    /// a full interval after the last draw: a late set would otherwise pass its lag on to the next, which then came less than
    /// the gap after it and waited too, and so on for good, with a timer per set.
    private func requestDraw() {
        let elapsed = lastDraw.map { now().timeIntervalSince($0) } ?? .infinity
        if elapsed >= Self.minimumGap {
            cancelPending()
            drawNow()
        } else if pending == nil {
            pending = scheduler.schedule(after: .seconds(Self.minimumGap - elapsed)) { [weak self] in
                self?.pending = nil
                guard let self, isOnScreen, isPlaying, spectrum != nil else { return }
                drawNow()
            }
        }
    }

    private func drawNow(animated: Bool = false) {
        let date = now()
        lastDraw = date
        let levels = NowPlayingBars.levels(spectrum: spectrum, isPlaying: isPlaying, at: date)
        guard levels != lastLevels else { return }
        lastLevels = levels
        draw(.levels(levels, animated: animated))
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}
