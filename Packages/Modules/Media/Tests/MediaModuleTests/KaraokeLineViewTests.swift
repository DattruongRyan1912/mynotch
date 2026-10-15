import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

/// The layers of one karaoke line: a dim text, the same text lit and masked, and the mask's one animation. Nothing is shown on a
/// screen: the views are never put in a window that is ordered in.
@Suite struct KaraokeLineViewTests {
    let origin = Date(timeIntervalSince1970: 8_000)
    let style = KaraokeStyle(fontSize: 12, weight: .semibold, lit: .white, dim: NSColor.white.withAlphaComponent(0.5))
    /// Sung from the first second: "one " 1…2 s, "two " 2…3 s, "three" 3…5 s.
    let line = LyricLine(time: 1, words: [
        LyricWord(text: "one ", begin: 1, end: 2), LyricWord(text: "two ", begin: 2, end: 3), LyricWord(text: "three", begin: 3, end: 5),
    ])

    func clock(elapsed: Double, playing: Bool = true, rate: Double = 1) -> KaraokeClock {
        KaraokeClock(NowPlayingState(
            bundleIdentifier: "x", title: "t", durationSeconds: 100,
            elapsedAnchor: PlaybackAnchor(elapsedSeconds: elapsed, timestamp: origin, rate: rate), isPlaying: playing
        ))
    }

    func makeView(width: CGFloat = 300) -> KaraokeLineView {
        let view = KaraokeLineView(now: { origin })
        view.frame = CGRect(x: 0, y: 0, width: width, height: 16)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func animation(_ view: KaraokeLineView) -> CAKeyframeAnimation? {
        view.fillMask.animation(forKey: KaraokeLineView.animationKey) as? CAKeyframeAnimation
    }

    /// Where the mask's layer sits when the fill is at `x`.
    func maskX(_ x: Double, in view: KaraokeLineView) -> Double {
        KaraokeSweep.edge(forFill: x, width: view.textWidth, feather: KaraokeStyle.feather) - view.textWidth
    }

    // MARK: layers

    @Test func theTextIsInTwoLayersTheSungOneMaskedByTheFill() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 0, playing: false), style: style)
        let layers = try #require(view.layer?.sublayers?.compactMap { $0 as? CATextLayer })
        #expect(layers.count == 2)
        #expect(layers.allSatisfy { ($0.string as? String) == "one two three" })
        #expect(view.litLayer.mask === view.fillMask)
        #expect(view.dimLayer.mask == nil)
        #expect(view.litLayer.foregroundColor == NSColor.white.cgColor)
        #expect(view.dimLayer.foregroundColor == NSColor.white.withAlphaComponent(0.5).cgColor)
        #expect(view.litLayer.fontSize == 12 && view.dimLayer.fontSize == 12)
    }

    @Test func aLineThatFitsIsCentredInTheRow() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 0, playing: false), style: style)
        #expect(view.textWidth > 0 && view.textWidth < 300)
        #expect(abs(view.litLayer.frame.midX - 150) < 0.5)
        #expect(view.litLayer.frame == view.dimLayer.frame)
        #expect(abs(view.litLayer.frame.midY - 8) < 0.5)
    }

    @Test func aLineTooWideForItsRowIsScaledDownAndCutAtItsEnd() {
        let long = LyricLine(time: 1, words: (0..<30).map { LyricWord(text: "word\($0) ", begin: 1 + Double($0), end: 2 + Double($0)) })
        let view = makeView(width: 200)
        view.show(line: long, clock: clock(elapsed: 0, playing: false), style: style)
        #expect(abs(view.litLayer.fontSize - 12 * KaraokeFit.minimumScale) < 1e-9)
        #expect(view.litLayer.frame.width <= 200)
        #expect(view.litLayer.truncationMode == .end)
        // A little too wide is scaled to fit and not cut.
        let slightly = LyricLine(time: 1, words: [LyricWord(text: "a fairly long line of words ", begin: 1, end: 2), LyricWord(text: "to sing", begin: 2, end: 3)])
        let narrow = makeView(width: 150)
        narrow.show(line: slightly, clock: clock(elapsed: 0, playing: false), style: style)
        #expect(narrow.litLayer.fontSize < 12 && narrow.litLayer.fontSize >= 12 * KaraokeFit.minimumScale)
    }

    @Test func aLineWithoutWordsIsShownLitAndWhole() {
        let view = makeView()
        view.show(line: LyricLine(time: 1, text: "plain line"), clock: clock(elapsed: 1.5), style: style)
        #expect(view.litLayer.mask == nil)
        #expect(animation(view) == nil)
        #expect((view.litLayer.string as? String) == "plain line")
        #expect(view.dimLayer.isHidden)
    }

    @Test func theViewLeavesClicksToTheSwiftUIViewItSitsIn() {
        #expect(makeView().hitTest(CGPoint(x: 5, y: 5)) == nil)
    }

    // MARK: the fill

    @Test func aPausedLineIsFilledUpToWhereItIsSungAndNothingMoves() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 2.5, playing: false), style: style)
        #expect(animation(view) == nil)
        let sweep = try #require(view.sweep)
        #expect(sweep.steps.isEmpty)
        // Half of "two ", so past the end of "one " and before the end of "two ".
        let ones = view.edges
        #expect(sweep.start > ones[1] && sweep.start < ones[2])
        #expect(abs(sweep.start - (ones[1] + ones[2]) / 2) < 1e-9)
        #expect(abs(Double(view.fillMask.position.x) - maskX(sweep.start, in: view)) < 1e-6)
    }

    @Test func beforeTheFirstWordNothingIsLitAndAfterTheLastEverythingIs() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 0, playing: false), style: style)
        #expect(abs(Double(view.fillMask.position.x) - maskX(0, in: view)) < 1e-6)
        // The mask's soft edge is wholly before the text.
        #expect(Double(view.fillMask.position.x) + Double(view.fillMask.bounds.width) <= 1e-6)
        view.show(line: line, clock: clock(elapsed: 9, playing: false), style: style)
        #expect(abs(Double(view.fillMask.position.x) - maskX(view.textWidth, in: view)) < 1e-6)
        #expect(Double(view.fillMask.position.x) <= 1e-6)
    }

    @Test func aPlayingLineIsOneAnimationOfTheMaskWhichTheRenderServerRuns() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        let keyframes = try #require(animation(view))
        let sweep = try #require(view.sweep)
        #expect(keyframes.keyPath == "position.x")
        #expect(abs(keyframes.duration - sweep.duration) < 1e-9)
        #expect(keyframes.calculationMode == .linear)
        #expect(keyframes.keyTimes?.map(\.doubleValue) == sweep.keyTimes)
        let values = try #require(keyframes.values as? [Double])
        #expect(values.count == sweep.steps.count + 1)
        #expect(abs(values[0] - maskX(sweep.start, in: view)) < 1e-6)
        #expect(abs(values[values.count - 1] - maskX(sweep.finish, in: view)) < 1e-6)
        // Afterwards the layer stays where the animation ends.
        #expect(abs(Double(view.fillMask.position.x) - maskX(sweep.finish, in: view)) < 1e-6)
        #expect(abs(sweep.finish - Double(view.textWidth)) < 1e-9)
    }

    @Test func aFasterClockMakesTheAnimationShorter() throws {
        let normal = makeView()
        normal.show(line: line, clock: clock(elapsed: 1.5), style: style)
        let fast = makeView()
        fast.show(line: line, clock: clock(elapsed: 1.5, rate: 2), style: style)
        let normalDuration = try #require(animation(normal)).duration
        let fastDuration = try #require(animation(fast)).duration
        #expect(abs(normalDuration / fastDuration - 2) < 1e-9)
    }

    @Test func theSameLineAndClockAgainLeaveTheRunningAnimationAlone() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.layoutSubtreeIfNeeded()
        #expect(view.buildCount == 1)
    }

    @Test func aSeekMakesANewAnimationFromWhereItLands() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        let before = try #require(view.sweep).start
        view.show(line: line, clock: clock(elapsed: 3.5), style: style)
        #expect(view.buildCount == 2)
        #expect(try #require(view.sweep).start > before)
        #expect(animation(view) != nil)
    }

    @Test func pausingTakesTheAnimationAwayAndKeepsTheFill() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.show(line: line, clock: clock(elapsed: 1.5, playing: false), style: style)
        #expect(animation(view) == nil)
        let sweep = try #require(view.sweep)
        #expect(abs(Double(view.fillMask.position.x) - maskX(sweep.start, in: view)) < 1e-6)
    }

    @Test func aLineThatIsAlreadySungHasNoAnimationAndIsAllLit() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 50), style: style)
        #expect(animation(view) == nil)
        #expect(abs(Double(view.fillMask.position.x) - maskX(view.textWidth, in: view)) < 1e-6)
    }

    @Test func aNewLineReplacesTheOldOne() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        let next = LyricLine(time: 6, words: [LyricWord(text: "four ", begin: 6, end: 7), LyricWord(text: "five", begin: 7, end: 8)])
        view.show(line: next, clock: clock(elapsed: 6.5), style: style)
        #expect((view.litLayer.string as? String) == "four five")
        #expect((view.dimLayer.string as? String) == "four five")
        #expect(try #require(view.sweep).steps.last?.x == view.textWidth)
    }

    // MARK: while the notch cannot be seen

    @Test func offScreenTheAnimationIsTakenAwayAndBackOnScreenItStartsAgainFromNow() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.isOnScreen = false
        #expect(animation(view) == nil)
        view.isOnScreen = true
        #expect(animation(view) != nil)
    }

    @Test func aLineShownWhileOffScreenIsNotAnimated() {
        let view = makeView()
        view.isOnScreen = false
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        #expect(animation(view) == nil)
        #expect(view.sweep != nil)
    }

    @Test func settingTheSameVisibilityAgainBuildsNothing() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.isOnScreen = true
        view.isOnScreen = true
        #expect(view.buildCount == 1)
    }

    @Test func aChangeOfWidthPlacesTheTextAgainAndKeepsTheFillInStep() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 2.5, playing: false), style: style)
        view.frame = CGRect(x: 0, y: 0, width: 500, height: 16)
        view.layoutSubtreeIfNeeded()
        #expect(abs(view.litLayer.frame.midX - 250) < 0.5)
        let sweep = try #require(view.sweep)
        #expect(abs(Double(view.fillMask.position.x) - maskX(sweep.start, in: view)) < 1e-6)
    }
}

/// The SwiftUI side: the line in a hosting view that is not shown, with the run loop doing what the display would. A window
/// that is not shown has no render server to hold animations, so Core Animation drops them at the first commit: these tests
/// ask the view whether it has started one (`isAnimating`) and the layers' own tests in the suite above look at the animation.
@Suite struct KaraokeLineHostingTests {
    func playingStore(elapsed: Double = 1.2) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(elapsed: elapsed), receivedAt: Date())
        return store
    }

    let line = LyricLine(time: 1, words: [
        LyricWord(text: "one ", begin: 1, end: 2), LyricWord(text: "two ", begin: 2, end: 3), LyricWord(text: "three", begin: 3, end: 30),
    ])
    let style = KaraokeStyle(fontSize: 12, weight: .semibold, lit: .white, dim: .gray)

    func host<Content: View>(_ content: Content) -> (CountingHostingView<Content>, NSWindow) {
        let hosting = CountingHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func karaokeView(in view: NSView) -> KaraokeLineView? {
        if let found = view as? KaraokeLineView { return found }
        for subview in view.subviews { if let found = karaokeView(in: subview) { return found } }
        return nil
    }

    func run(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @Test func theLineSweepsInAViewOfItsOwnInsideTheHostingView() throws {
        let store = playingStore()
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16))
        run(for: 0.05)
        let view = try #require(karaokeView(in: hosting))
        #expect(view.isAnimating)
        window.contentView = nil
    }

    /// The point of the layer: the fill moves with no pass of SwiftUI's, so the notch never lays out for it.
    @Test func theSweepNeverLaysTheHostingViewOutAgain() throws {
        let store = playingStore()
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16))
        run(for: 0.05)
        let layouts = hosting.layouts
        run(for: 0.3)
        #expect(hosting.layouts == layouts)
        #expect(!hosting.needsLayout)
        window.contentView = nil
    }

    @Test func aPauseReachesTheLayerAndTakesTheAnimationAway() throws {
        let store = playingStore()
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16))
        run(for: 0.05)
        let view = try #require(karaokeView(in: hosting))
        store.apply(line: AdapterLines.playing(false), receivedAt: Date())
        run(for: 0.1)
        #expect(!view.isAnimating)
        store.apply(line: AdapterLines.playing(true), receivedAt: Date())
        run(for: 0.1)
        #expect(view.isAnimating)
        window.contentView = nil
    }

    @Test func aSeekReachesTheLayer() throws {
        let store = playingStore(elapsed: 1.2)
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16))
        run(for: 0.05)
        let view = try #require(karaokeView(in: hosting))
        let before = try #require(view.sweep).start
        store.apply(line: AdapterLines.position(2.6), receivedAt: Date())
        run(for: 0.1)
        #expect(try #require(view.sweep).start > before)
        window.contentView = nil
    }

    @Test func aHiddenNotchStopsTheAnimation() throws {
        let store = playingStore()
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16).environment(\.notchIsOnScreen, false))
        run(for: 0.05)
        let view = try #require(karaokeView(in: hosting))
        #expect(!view.isAnimating)
        window.contentView = nil
    }
}
