#if DEBUG
import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import Testing
@testable import MediaModule

/// What the collapsed notch's bars cost on two displays, counted over one simulated second: redraws of the bars
/// (`NotchPerf.spectrumUpdates`) and the timers the driver asked the scheduler for, each a `Task.sleep` and a main-actor hop.
///
/// Before (the bars at `bde69bb`, one driver and one timer chain per view, two displays):
///
///     made-up motion (no real spectrum, the default)   60 redraws, 60 timers
///     tap at 30 Hz                                     60 redraws,  0 timers
///     tap at 60 Hz, a fake feed twice the real rate    82 redraws, 80 timers
///
/// The ceilings below are what it is now; none of them may creep back.
@Suite struct SpectrumLoadTests {
    /// Counts what is scheduled on a manual clock.
    final class CountingScheduler: Scheduler {
        let inner = ManualScheduler()
        private(set) var scheduled = 0

        @discardableResult
        func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ScheduledAction {
            scheduled += 1
            return inner.schedule(after: delay, action)
        }
    }

    struct Rig {
        let store: NowPlayingStore
        let scheduler: CountingScheduler
        let windows: [NSWindow]

        func finish() { windows.forEach { $0.contentView = nil } }
    }

    /// A playing store with the bars of `displays` displays on screen: one view each, as the notch of each display has.
    func rig(displays: Int) -> (Rig, [SpectrumBarsView]) {
        let scheduler = CountingScheduler()
        let epoch = Date(timeIntervalSinceReferenceDate: 1_000)
        let store = NowPlayingStore(lookUpApp: { _ in nil }, scheduler: scheduler, now: {
            epoch + Double(scheduler.inner.now.components.seconds) + Double(scheduler.inner.now.components.attoseconds) / 1e18
        })
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        var views: [SpectrumBarsView] = []
        var windows: [NSWindow] = []
        for _ in 0..<displays {
            let view = SpectrumBarsView(store: store, accent: CGColor(gray: 1, alpha: 1))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 30), styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = view
            view.frame = CGRect(origin: .zero, size: NowPlayingBars.size)
            views.append(view)
            windows.append(window)
        }
        return (Rig(store: store, scheduler: scheduler, windows: windows), views)
    }

    /// Redraws and timers over one second in which a set of bands arrives `rate` times.
    func tapCost(displays: Int, rate: Int) -> (updates: Int, timers: Int) {
        let (rig, views) = rig(displays: displays)
        defer { rig.finish() }
        rig.store.showSpectrum([0, 0, 0, 0])
        rig.scheduler.inner.advance(by: .milliseconds(100))
        let updates = NotchPerf.counted(.spectrumUpdates)
        let timers = rig.scheduler.scheduled
        for step in 1...rate {
            rig.scheduler.inner.advance(by: .nanoseconds(1_000_000_000 / rate))
            rig.store.showSpectrum([Float(step) / 100, 0.5, 0.5, 0.5])
        }
        rig.scheduler.inner.advance(by: .milliseconds(100))
        _ = views
        return (NotchPerf.counted(.spectrumUpdates) - updates, rig.scheduler.scheduled - timers)
    }

    @Test func madeUpMotionOnTwoDisplaysRedrawsAndSchedulesNothing() {
        let (rig, views) = rig(displays: 2)
        defer { rig.finish() }
        #expect(views.allSatisfy { $0.isMadeUp })
        let updates = NotchPerf.counted(.spectrumUpdates)
        let timers = rig.scheduler.scheduled
        rig.scheduler.inner.advance(by: .seconds(1))
        #expect(NotchPerf.counted(.spectrumUpdates) - updates == 0)
        #expect(rig.scheduler.scheduled - timers == 0)
    }

    @Test func aFakeSixtyHertzFeedOnTwoDisplaysIsDrawnOncePerSetAndAtMostFortyOneTimesASecond() {
        let cost = tapCost(displays: 2, rate: 60)
        #expect(cost.updates <= 42, "\(cost.updates) redraws; there were 82")
        #expect(cost.updates >= 30)
        #expect(cost.timers <= 41, "\(cost.timers) timers; there were 80")
    }

    @Test func aThirtyHertzTapOnTwoDisplaysIsThirtyRedrawsASecondAndNoTimer() {
        let cost = tapCost(displays: 2, rate: 30)
        #expect(cost.updates == 30, "\(cost.updates) redraws; there were 60")
        #expect(cost.timers == 0)
    }

    @Test func moreDisplaysAddNoRedrawsAndNoTimers() {
        let one = tapCost(displays: 1, rate: 60)
        let three = tapCost(displays: 3, rate: 60)
        #expect(three.updates == one.updates)
        #expect(three.timers == one.timers)
    }
}
#endif
