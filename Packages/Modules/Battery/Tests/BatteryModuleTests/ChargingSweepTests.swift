import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import BatteryModule

/// The sweep's view on its own: where its animation exists and what it is made of, with a clock the test holds still.
@Suite struct ChargingSweepViewTests {
    /// A moment a quarter of the way through a sweep: 0.65 s past a whole number of 2.6 s periods.
    static let quarter = Date(timeIntervalSinceReferenceDate: 2.6 * 1000 + 0.65)

    func window(holding view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = view
        return window
    }

    func animation(of view: ChargingSweepView) -> CABasicAnimation? {
        view.band.animation(forKey: ChargingSweepView.animationKey) as? CABasicAnimation
    }

    @Test func theAnimationExistsOnlyWhileTheViewIsInAWindow() {
        let view = ChargingSweepView(fillWidth: 300, now: { Self.quarter })
        #expect(!view.isSweeping)
        let window = window(holding: view)
        #expect(view.isSweeping)
        #expect(view.animationStarts == 1)
        window.contentView = nil
        #expect(!view.isSweeping)
        // Back in a window it sweeps again, with an animation added afresh.
        let again = self.window(holding: view)
        #expect(view.isSweeping)
        #expect(view.animationStarts == 2)
        again.contentView = nil
    }

    @Test func theBandCrossesTheFillFromJustOutsideItsLeftEndToJustOutsideItsRightEndOverEverySweep() throws {
        let view = ChargingSweepView(fillWidth: 300, now: { Self.quarter })
        let window = window(holding: view)
        let sweep = try #require(animation(of: view))
        #expect(sweep.keyPath == "position.x")
        // The band's centre: half its width left of the fill's left end to half its width right of the right end.
        #expect(sweep.fromValue as? CGFloat == -35)
        #expect(sweep.toValue as? CGFloat == 335)
        #expect(sweep.duration == 2.6)
        #expect(sweep.repeatCount == .infinity)
        #expect(!sweep.autoreverses)
        // Sixty frames a second at most and at least, as the timeline it replaced.
        #expect(sweep.preferredFrameRateRange == CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60))
        window.contentView = nil
    }

    @Test func theAnimationBeginsAtTheWallClocksPlaceInTheSweep() throws {
        let view = ChargingSweepView(fillWidth: 300, now: { Self.quarter })
        let window = window(holding: view)
        let sweep = try #require(animation(of: view))
        #expect(abs(sweep.timeOffset - 0.65) < 1e-6)
        window.contentView = nil
    }

    @Test func aNewWidthCarriesTheSweepOnFromWhereItIs() throws {
        var clock = Self.quarter
        let view = ChargingSweepView(fillWidth: 300, now: { clock })
        let window = window(holding: view)
        #expect(view.animationStarts == 1)

        // The same width again is nothing to start over for.
        view.fillWidth = 300
        #expect(view.animationStarts == 1)

        view.fillWidth = 200
        #expect(view.animationStarts == 2)
        var sweep = try #require(animation(of: view))
        #expect(sweep.toValue as? CGFloat == 235)
        #expect(abs(sweep.timeOffset - 0.65) < 1e-6, "no clock moved, so the sweep is where it was")

        clock = clock.addingTimeInterval(1)
        view.fillWidth = 250
        sweep = try #require(animation(of: view))
        #expect(sweep.toValue as? CGFloat == 285)
        #expect(abs(sweep.timeOffset - 1.65) < 1e-6, "a second later")
        window.contentView = nil
    }

    @Test func theBandIsAGradientOfWhiteThatPeaksInTheMiddleAtAQuarterOpacityAndFadesToNothingAtBothEnds() throws {
        let view = ChargingSweepView(fillWidth: 300)
        let colors = try #require(view.band.colors as? [CGColor])
        #expect(colors.count == 3)
        #expect(colors.map(\.alpha) == [0, 0.25, 0])
        for color in colors {
            #expect(color.components?.prefix(3).allSatisfy { $0 == 1 } == true, "white at every stop, so nothing grey in between")
        }
        #expect(view.band.startPoint == CGPoint(x: 0, y: 0.5))
        #expect(view.band.endPoint == CGPoint(x: 1, y: 0.5))
        #expect(view.band.locations == nil, "evenly spaced")
    }

    @Test func theBandIsSeventyPointsWideAsTallAsTheFillAndClippedToItsRoundedShapeOutsideItAtRest() {
        let view = ChargingSweepView(fillWidth: 300)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 36)
        view.layoutSubtreeIfNeeded()
        #expect(view.clip.frame == view.bounds)
        #expect(view.clip.masksToBounds)
        #expect(view.clip.cornerRadius == BatteryGaugeLayout.fillRadius)
        #expect(view.band.bounds.size == CGSize(width: 70, height: 36))
        // Where the sweep begins, wholly outside the fill: nothing shows of it while nothing animates it.
        #expect(view.band.frame.maxX <= 0)
    }

    @Test func theViewPaintsNothingOfItsOwnAndLeavesClicksToWhatIsUnderIt() {
        let view = ChargingSweepView(fillWidth: 300)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 36)
        #expect(view.hitTest(CGPoint(x: 10, y: 10)) == nil)
    }
}

/// The Battery tab hosted in a window that is never shown. A layer in such a window loses its animations at the next turn of the run
/// loop (a bare `CALayer` does too), so where a test spins the run loop it reads whether the sweep view is there and what it did on the
/// way in (`animationStarts`), and the layer's own animation is read right after the hosting, before anything has turned.
enum SweepHarness {
    static func chargingState(isTabVisible: Bool = true, isCharging: Bool = true) -> BatteryState {
        let state = BatteryState()
        state.snapshot = PowerSourceSnapshot(percent: 80, isCharging: isCharging, isOnAC: true, minutesToFull: 80)
        state.isTabVisible = isTabVisible
        return state
    }

    static func tab(_ state: BatteryState, onScreen: Bool = true) -> AnyView {
        AnyView(
            BatteryTabView(state: state, actions: BatteryTabActions(appeared: {}, disappeared: {}))
                .frame(width: 452, height: 160)
                .environment(\.notchIsOnScreen, onScreen)
        )
    }

    static func host(_ state: BatteryState, onScreen: Bool = true) -> (CountingHostingView<AnyView>, NSWindow) {
        let hosting = CountingHostingView(rootView: tab(state, onScreen: onScreen))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 452, height: 160), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    static func sweep(in view: NSView) -> ChargingSweepView? {
        if let sweep = view as? ChargingSweepView { return sweep }
        for subview in view.subviews {
            if let sweep = sweep(in: subview) { return sweep }
        }
        return nil
    }
}

/// The sweep inside the Battery tab, with a charging battery.
@Suite struct ChargingSweepInTheTabTests {
    typealias Harness = SweepHarness

    @Test func aChargingBatteryOnAVisibleTabInAWindowOnScreenSweeps() throws {
        let (hosting, window) = Harness.host(Harness.chargingState())
        let view = try #require(Harness.sweep(in: hosting))
        #expect(view.isSweeping)
        #expect(view.animationStarts == 1)
        window.contentView = nil
    }

    @Test func theSweepViewIsAsBigAsTheFillSoTheBandCrossesAllOfIt() throws {
        let (hosting, window) = Harness.host(Harness.chargingState())
        let view = try #require(Harness.sweep(in: hosting))
        // 452 pt, less the terminal (4) and its gap (2): a body 446 wide; the fill is 80 % of what is inside the outline and the inset.
        let layout = BatteryGaugeLayout(percent: 80, bodyWidth: 446)
        #expect(abs(view.bounds.width - layout.fillWidth) < 0.5)
        #expect(view.fillWidth == layout.fillWidth)
        #expect(view.bounds.height == BatteryGaugeLayout.height - 2 * (BatteryGaugeLayout.outlineWidth + BatteryGaugeLayout.inset))
        window.contentView = nil
    }

    @Test func aBatteryThatIsNotChargingHasNoSweepAtAll() {
        let (hosting, window) = Harness.host(Harness.chargingState(isCharging: false))
        #expect(Harness.sweep(in: hosting) == nil)
        window.contentView = nil
    }

    @Test func aTabThatIsNotOnScreenHasNoSweep() {
        let (hosting, window) = Harness.host(Harness.chargingState(isTabVisible: false))
        #expect(Harness.sweep(in: hosting) == nil)
        window.contentView = nil
    }

    @Test func aNotchThatIsHiddenHasNoSweep() {
        let (hosting, window) = Harness.host(Harness.chargingState(), onScreen: false)
        #expect(Harness.sweep(in: hosting) == nil)
        window.contentView = nil
    }

    @Test func theSweepStopsWhenTheChargerIsUnpluggedAndStartsAgainWhenItIsPluggedBackIn() throws {
        let state = Harness.chargingState()
        let (hosting, window) = Harness.host(state)
        #expect(Harness.sweep(in: hosting) != nil)

        state.snapshot = PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: false)
        #expect(runLoop(until: { Harness.sweep(in: hosting) == nil }))

        state.snapshot = PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true, minutesToFull: 80)
        #expect(runLoop(until: { Harness.sweep(in: hosting) != nil }))
        // A new view, and it began its sweep when it came into the window.
        #expect(try #require(Harness.sweep(in: hosting)).animationStarts == 1)
        window.contentView = nil
    }

    @Test func theSweepStopsWhenTheTabLeavesTheScreenAndWhenTheNotchIsHiddenAndComesBack() throws {
        let state = Harness.chargingState()
        let (hosting, window) = Harness.host(state)
        #expect(Harness.sweep(in: hosting) != nil)

        state.isTabVisible = false
        #expect(runLoop(until: { Harness.sweep(in: hosting) == nil }))
        state.isTabVisible = true
        #expect(runLoop(until: { Harness.sweep(in: hosting) != nil }))

        // A fullscreen app in front, a locked screen, a display asleep.
        hosting.rootView = Harness.tab(state, onScreen: false)
        #expect(runLoop(until: { Harness.sweep(in: hosting) == nil }))
        hosting.rootView = Harness.tab(state, onScreen: true)
        #expect(runLoop(until: { Harness.sweep(in: hosting) != nil }))
        #expect(try #require(Harness.sweep(in: hosting)).animationStarts == 1)
        window.contentView = nil
    }

    @Test func theSweepStopsWhenTheNotchLeavesItsWindow() throws {
        let (hosting, window) = Harness.host(Harness.chargingState())
        let view = try #require(Harness.sweep(in: hosting))
        #expect(view.isSweeping)
        window.contentView = nil
        #expect(!view.isSweeping)
    }
}

/// The point of the change, as the notch's perf lab counts it: a simulated second of the run loop with a charging battery and the tab
/// on screen. The sweep used to be a `TimelineView(.animation(minimumInterval: 1 / 60))`, measured on the tab at `f937bf3`: 60 body
/// evaluations a second, and a hosting view that never went quiet (14,000 to 30,000 layout passes a second, one for every turn of the run
/// loop that a tick had invalidated). Now: 0 evaluations, 0 layout passes, and the animation added once, on the way in. The control below
/// is that timeline, kept here to show that the harness sees such work at all.
@Suite struct ChargingSweepPerfTests {
    typealias Harness = SweepHarness

    final class Evaluations {
        var count = 0
    }

    /// The sweep as it was: the same gradient, driven by a timeline that asks for a new body at the display's rate (capped at 60).
    struct TimelineSweep: View {
        let fillWidth: CGFloat
        let evaluations: Evaluations

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                let phase = BatteryGaugeMotion.sweepPhase(at: timeline.date.timeIntervalSinceReferenceDate)
                let _ = { evaluations.count += 1 }()
                LinearGradient(colors: [.clear, .white.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 70)
                    .offset(x: -70 + phase * (fillWidth + 70))
            }
        }
    }

    @Test func theControlTimelineEvaluatesItsBodyEveryFrameAndKeepsTheHostingViewBusy() {
        let evaluations = Evaluations()
        let hosting = CountingHostingView(rootView: TimelineSweep(fillWidth: 349, evaluations: evaluations).frame(width: 349, height: 36))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 349, height: 36), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let before = evaluations.count
        let layouts = hosting.layouts
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        #expect(evaluations.count - before >= 30, "a timeline at 60 fps evaluates about 60 times a second; it did \(evaluations.count - before)")
        #expect(hosting.layouts > layouts)
        window.contentView = nil
    }

    @Test func aSecondOfChargingEvaluatesNothingAndLaysNothingOutWhileTheSweepPlays() throws {
        let (hosting, window) = Harness.host(Harness.chargingState())
        let view = try #require(Harness.sweep(in: hosting))
        runLoopUntilQuiet { hosting.layouts }

        let layouts = hosting.layouts
        let starts = view.animationStarts
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        // No tick, no update of the view, no layout of the notch: the render server is the only one moving the band.
        #expect(hosting.layouts == layouts)
        #expect(!hosting.needsLayout)
        #expect(view.animationStarts == starts)
        #expect(view.animationStarts == 1)
        #expect(view.window != nil)
        window.contentView = nil
    }
}
