import Foundation
import MyNotchCore

/// Decides what the bars show and when it is drawn, so the bars' view only draws what it is handed. The bars draw only while
/// they are on screen with something playing. New bands from the tap draw the moment they arrive, with no timer: the tap
/// delivers about 30 sets a second, and a source faster than that is thinned to at most 40 draws a second. The made-up motion
/// steps 30 times a second on a timer of its own. Time comes from the scheduler and `now`, so tests move it by hand.
final class BarsDriver {
    /// Time between two redraws: the tap delivers about 30 sets a second, and the made-up motion steps at this rate.
    static let interval: Duration = .nanoseconds(33_333_333)
    private static let intervalSeconds: TimeInterval = 0.033_333_333
    /// The least time between two draws of tap bands. The tap's timer has 5 ms of leeway, so its sets come 28 to 38 ms apart;
    /// holding back the early ones for a full interval cost a `Task.sleep` and a main-actor hop each and drifted the rate to
    /// 28 a second. A quarter of an interval short is drawn on arrival; only a faster source waits for its slot.
    private static let minimumGap: TimeInterval = intervalSeconds * 0.75

    private let scheduler: any Scheduler
    private let now: () -> Date
    private let draw: ([Double], _ animated: Bool) -> Void
    private var isOnScreen = false
    private var isPlaying = false
    private var spectrum: [Float]?
    private var lastLevels: [Double]?
    private var lastDraw: Date?
    /// The next step of the made-up motion.
    private var step: ScheduledAction?
    /// A set of bands that arrived too soon after the last draw; it draws the latest bands when its slot comes.
    private var pending: ScheduledAction?

    /// `draw` gets one level in 0…1 per bar and whether to ease to it instead of jumping.
    init(scheduler: any Scheduler, now: @escaping () -> Date = Date.init, draw: @escaping ([Double], _ animated: Bool) -> Void) {
        self.scheduler = scheduler
        self.now = now
        self.draw = draw
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
            cancelStep()
            requestDraw()
        }
    }

    private func restart(animated: Bool) {
        cancelStep()
        cancelPending()
        guard isOnScreen else { return }
        if isPlaying && spectrum == nil {
            tick()
        } else {
            drawNow(animated: animated)
        }
    }

    /// One step of the made-up motion, and the schedule of the next.
    private func tick() {
        step = nil
        guard isOnScreen, isPlaying, spectrum == nil else { return }
        drawNow()
        step = scheduler.schedule(after: Self.interval) { [weak self] in self?.tick() }
    }

    /// Draws now, or in the slot after the last draw when the set came much too soon.
    private func requestDraw() {
        let elapsed = lastDraw.map { now().timeIntervalSince($0) } ?? .infinity
        if elapsed >= Self.minimumGap {
            cancelPending()
            drawNow()
        } else if pending == nil {
            pending = scheduler.schedule(after: .seconds(Self.intervalSeconds - elapsed)) { [weak self] in
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
        draw(levels, animated)
    }

    private func cancelStep() {
        step?.cancel()
        step = nil
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}
