import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import Testing
@testable import MediaModule

/// The made-up motion of the bars as an animation of their layers, and the one hub that serves every display.
@Suite struct SpectrumMadeUpTests {
    let scheduler: ManualScheduler
    let store: NowPlayingStore
    let accent = CGColor(gray: 1, alpha: 1)

    init() {
        let scheduler = ManualScheduler()
        self.scheduler = scheduler
        store = NowPlayingStore(lookUpApp: { _ in nil }, scheduler: scheduler, now: SpectrumBarsViewTests.clock(of: scheduler))
        store.apply(line: AdapterLines.track(), receivedAt: Date())
    }

    var epoch: Date { SpectrumBarsViewTests.epoch }
    var now: Date { SpectrumBarsViewTests.clock(of: scheduler)() }

    func attach(_ view: SpectrumBarsView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 30), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = view
        view.frame = CGRect(origin: .zero, size: NowPlayingBars.size)
        view.layoutSubtreeIfNeeded()
        return window
    }

    func bars(_ view: SpectrumBarsView) -> [CALayer] { view.layer?.sublayers ?? [] }

    func loop(of bar: CALayer) -> CAKeyframeAnimation? {
        bar.animation(forKey: SpectrumBarsView.madeUpKey) as? CAKeyframeAnimation
    }

    // MARK: - The loop

    @Test func theMadeUpMotionComesBackToWhereItWasEveryLoopSoTheLoopHasNoSeam() {
        #expect(abs(NowPlayingBars.madeUpLoop - 62.83) < 0.01)
        for bar in 0..<NowPlayingBars.barCount {
            for second in stride(from: 0.0, to: NowPlayingBars.madeUpLoop, by: 1.37) {
                let first = NowPlayingBars.level(bar: bar, at: Date(timeIntervalSinceReferenceDate: second))
                let again = NowPlayingBars.level(bar: bar, at: Date(timeIntervalSinceReferenceDate: second + NowPlayingBars.madeUpLoop))
                #expect(abs(first - again) < 1e-9, "bar \(bar) at \(second) s")
            }
        }
    }

    @Test func theLoopHoldsThirtyStepsASecond() {
        #expect(NowPlayingBars.madeUpKeyframeCount == 1885)
        let step = NowPlayingBars.madeUpLoop / Double(NowPlayingBars.madeUpKeyframeCount)
        #expect(abs(1 / step - 30) < 0.001)
        for bar in 0..<NowPlayingBars.barCount {
            let heights = NowPlayingBars.madeUpHeights(bar: bar)
            #expect(heights.count == NowPlayingBars.madeUpKeyframeCount)
            for index in [0, 1, 500, 1884] {
                let level = NowPlayingBars.level(bar: bar, at: Date(timeIntervalSinceReferenceDate: Double(index) * step))
                #expect(heights[index] == NowPlayingBars.height(forLevel: level))
            }
            #expect(heights.allSatisfy { (NowPlayingBars.minHeight...NowPlayingBars.maxHeight).contains($0) })
        }
    }

    @Test func thePhaseIsThePlaceInTheLoopForTheWallClock() {
        let loop = NowPlayingBars.madeUpLoop
        #expect(NowPlayingBars.madeUpPhase(at: Date(timeIntervalSinceReferenceDate: 3 * loop + 5)) - 5 < 1e-6)
        #expect((0..<loop).contains(NowPlayingBars.madeUpPhase(at: Date(timeIntervalSinceReferenceDate: 800_000_000.5))))
    }

    // MARK: - The animation

    @Test func theBarsOfAPlayingStoreRunTheMadeUpMotionAsAnAnimationOfEachLayer() throws {
        let view = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view)
        #expect(view.isMadeUp)
        for (index, bar) in bars(view).enumerated() {
            let animation = try #require(loop(of: bar))
            #expect(animation.keyPath == "bounds.size.height")
            #expect(animation.calculationMode == .discrete, "held at 30 steps a second, never blended in between")
            #expect(animation.repeatCount == .infinity)
            #expect(animation.duration == NowPlayingBars.madeUpLoop)
            #expect(animation.timeOffset == NowPlayingBars.madeUpPhase(at: epoch))
            #expect((animation.values?.count ?? 0) == NowPlayingBars.madeUpKeyframeCount)
            #expect(animation.values?.first as? Double == Double(NowPlayingBars.madeUpHeights(bar: index)[0]))
            #expect(animation.preferredFrameRateRange == CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30), "not at the display's rate")
            // What the layer holds without the animation is the height it begins at.
            let begins = NowPlayingBars.height(forLevel: NowPlayingBars.level(bar: index, at: Date(timeIntervalSinceReferenceDate: NowPlayingBars.madeUpPhase(at: epoch))))
            #expect(abs(bar.frame.height - begins) < 0.0001)
            #expect(abs(bar.frame.midY - 7) < 0.0001)
        }
        window.contentView = nil
    }

    @Test func theMadeUpMotionNeedsNoTimerAndDrawsNothingPerStep() {
        let view = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view)
        #expect(scheduler.pendingCount == 0)
        let updates = NotchPerf.counted(.spectrumUpdates)
        scheduler.advance(by: .seconds(30))
        #expect(scheduler.pendingCount == 0)
        #expect(NotchPerf.counted(.spectrumUpdates) == updates)
        #expect(view.isMadeUp)
        window.contentView = nil
    }

    @Test func pausingTakesTheAnimationAwayAndEasesTheBarsToRest() async throws {
        let view = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view)
        #expect(view.isMadeUp)
        store.apply(line: AdapterLines.playing(false), receivedAt: Date())
        for _ in 0..<100 where view.isMadeUp { await Task.yield() }
        #expect(!view.isMadeUp)
        #expect(bars(view).allSatisfy { loop(of: $0) == nil })
        #expect(bars(view).allSatisfy { abs($0.frame.height - NowPlayingBars.minHeight) < 0.0001 })
        window.contentView = nil
    }

    @Test func theTapsBandsReplaceTheAnimationAndItsStoppingBringsItBack() throws {
        let view = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view)
        store.showSpectrum([0.5, 0.5, 0.5, 0.5])
        #expect(!view.isMadeUp)
        #expect(bars(view).allSatisfy { loop(of: $0) == nil })
        #expect(bars(view).allSatisfy { abs($0.frame.height - NowPlayingBars.height(forLevel: 0.5)) < 0.0001 })
        store.showSpectrum(nil)
        #expect(view.isMadeUp)
        #expect(bars(view).allSatisfy { loop(of: $0) != nil })
        window.contentView = nil
    }

    @Test func offScreenThereIsNoAnimationForTheRenderServerToCarry() {
        let view = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view)
        view.isNotchOnScreen = false
        #expect(!view.isMadeUp)
        #expect(bars(view).allSatisfy { $0.animationKeys() == nil })
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: .seconds(10))
        view.isNotchOnScreen = true
        #expect(view.isMadeUp)
        let animation = loop(of: bars(view)[0])
        #expect(animation?.timeOffset == NowPlayingBars.madeUpPhase(at: epoch + 10), "it picks up at the wall clock's place in the loop")
        window.contentView = nil
    }

    @Test func aViewThatLeavesItsWindowLetsGoOfTheAnimation() {
        let view = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view)
        window.contentView = nil
        #expect(!view.isMadeUp)
        #expect(bars(view).allSatisfy { $0.animationKeys() == nil })
    }

    @Test func aColourChangeLeavesTheAnimationRunning() {
        let view = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view)
        store.showTint(ArtworkPalette(primary: SRGBColor(red: 0.9, green: 0.2, blue: 0.1), secondary: SRGBColor(red: 0.1, green: 0.4, blue: 0.9)))
        #expect(view.isMadeUp)
        #expect(bars(view).allSatisfy { loop(of: $0) != nil })
        window.contentView = nil
    }

    @Test func aResizeKeepsTheAnimationAndTheCentre() {
        let view = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view)
        view.frame = CGRect(x: 0, y: 0, width: 40, height: 30)
        view.layoutSubtreeIfNeeded()
        #expect(bars(view).allSatisfy { loop(of: $0) != nil })
        #expect(bars(view).allSatisfy { abs($0.frame.midY - 15) < 0.0001 })
        window.contentView = nil
    }

    // MARK: - One hub for every display

    @Test func twoDisplaysShareOneDriverAndShowTheSameMotionAtTheSameMoment() throws {
        let first = SpectrumBarsView(store: store, accent: accent)
        let second = SpectrumBarsView(store: store, accent: accent)
        let windows = [attach(first), attach(second)]
        #expect(store.barsHub.viewCount == 2)
        #expect(store.spectrumViewCount == 2)
        for (a, b) in zip(bars(first), bars(second)) {
            let (one, two) = (try #require(loop(of: a)), try #require(loop(of: b)))
            #expect(one.timeOffset == two.timeOffset)
            #expect(one.values as? [Double] == two.values as? [Double])
        }
        windows.forEach { $0.contentView = nil }
        #expect(store.barsHub.viewCount == 0)
    }

    @Test func aViewThatJoinsLaterIsShownWhatTheOtherShows() {
        let first = SpectrumBarsView(store: store, accent: accent)
        let windows = [attach(first)]
        store.showSpectrum([0.25, 0.5, 0.75, 1])
        scheduler.advance(by: .milliseconds(100))
        let second = SpectrumBarsView(store: store, accent: accent)
        let joined = attach(second)
        #expect(!second.isMadeUp)
        #expect(bars(second).map(\.frame.height) == bars(first).map(\.frame.height))
        joined.contentView = nil
        windows.forEach { $0.contentView = nil }
    }

    @Test func theTapsBandsAreDrawnOncePerSetNoMatterHowManyDisplaysShowThem() {
        let views = (0..<3).map { _ in SpectrumBarsView(store: store, accent: accent) }
        let windows = views.map(attach)
        store.showSpectrum([0, 0, 0, 0])
        scheduler.advance(by: .milliseconds(100))
        let updates = NotchPerf.counted(.spectrumUpdates)
        store.showSpectrum([0.2, 0.4, 0.6, 0.8])
        #expect(NotchPerf.counted(.spectrumUpdates) == updates + 1)
        for view in views {
            #expect(bars(view).map(\.frame.height).allSatisfy { $0 > NowPlayingBars.minHeight })
            #expect(abs(bars(view)[3].frame.height - NowPlayingBars.height(forLevel: Double(Float(0.8)))) < 0.0001)
        }
        windows.forEach { $0.contentView = nil }
    }

    @Test func theHubFollowsTheStoreOnlyWhileAViewIsOnScreen() {
        let view = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view)
        window.contentView = nil
        let updates = NotchPerf.counted(.spectrumUpdates)
        store.showSpectrum([1, 1, 1, 1])
        store.showSpectrum([0.5, 0.5, 0.5, 0.5])
        scheduler.advance(by: .seconds(5))
        #expect(NotchPerf.counted(.spectrumUpdates) == updates)
        #expect(scheduler.pendingCount == 0)
        #expect(store.barsHub.viewCount == 0)
    }

    @Test func aViewThatIsFreedLeavesTheHub() {
        var view: SpectrumBarsView? = SpectrumBarsView(store: store, accent: accent)
        let window = attach(view!)
        #expect(store.barsHub.viewCount == 1)
        window.contentView = nil
        view = nil
        #expect(store.barsHub.viewCount == 0)
    }
}
