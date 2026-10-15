import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The vertical recognizer as a state machine fed with what a trackpad sends: a finger phase per event, then momentum
/// events with no finger phase, and a mouse wheel with neither. Positive `dy` is fingers moving down.
@Suite struct OpenSwipeTests {
    typealias Step = NotchSwipeRecognizer.Step

    final class Trackpad {
        var recognizer = NotchSwipeRecognizer()
        var sensitivity = SwipeSensitivity.medium
        /// Whether the pointer is on the notch; read by the recognizer when a gesture begins.
        var onNotch = true

        func feed(_ phase: NSEvent.Phase, _ dx: CGFloat = 0, _ dy: CGFloat = 0, momentum: NSEvent.Phase = []) -> Step? {
            recognizer.feed(phase: phase, momentumPhase: momentum, deltaX: dx, deltaY: dy, onNotch: onNotch, sensitivity: sensitivity)
        }

        func gesture(_ moves: [(dx: CGFloat, dy: CGFloat)]) -> [Step] {
            var steps: [Step] = []
            steps += feed(.began).map { [$0] } ?? []
            for move in moves { steps += feed(.changed, move.dx, move.dy).map { [$0] } ?? [] }
            steps += feed(.ended).map { [$0] } ?? []
            return steps
        }
    }

    @Test func aSwipeDownStepsOnceItHasTravelledFarEnough() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, 0, 10) == nil)
        #expect(pad.feed(.changed, 0, 15) == nil)
        #expect(pad.feed(.changed, 0, 15) == .down)
    }

    @Test func aSwipeUpIsTheOppositeStep() {
        let pad = Trackpad()
        #expect(pad.gesture([(0, -15), (0, -15), (0, -15)]) == [.up])
    }

    @Test func aShortSwipeDoesNothing() {
        let pad = Trackpad()
        #expect(pad.gesture([(0, 10), (0, 10), (0, 10)]).isEmpty)
    }

    @Test func aGestureStepsOnlyOnceHoweverFarItGoes() {
        let pad = Trackpad()
        #expect(pad.gesture(Array(repeating: (0, 30), count: 20)) == [.down])
    }

    @Test func goingBackAndForthCountsTheNetDistance() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, 0, 30) == nil)
        #expect(pad.feed(.changed, 0, -50) == nil)
        #expect(pad.feed(.changed, 0, -30) == .up)
    }

    @Test func aNewGestureStartsFromZeroAndCanStepAgain() {
        let pad = Trackpad()
        #expect(pad.gesture([(0, 30)]).isEmpty)
        #expect(pad.gesture([(0, 30)]).isEmpty)
        #expect(pad.gesture([(0, 60)]) == [.down])
        #expect(pad.gesture([(0, -60)]) == [.up])
        #expect(pad.gesture([(0, 60)]) == [.down])
    }

    // MARK: what is not a swipe

    @Test func momentumAfterTheFingersLiftNeverStepsAgain() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, 0, 50) == .down)
        #expect(pad.feed(.ended) == nil)
        #expect(pad.feed([], 0, 80, momentum: .began) == nil)
        for _ in 0..<10 { #expect(pad.feed([], 0, 80, momentum: .changed) == nil) }
        #expect(pad.feed([], 0, 0, momentum: .ended) == nil)
    }

    @Test func momentumAloneNeverStepsEvenAfterAShortGesture() {
        let pad = Trackpad()
        #expect(pad.gesture([(0, 10), (0, 10)]).isEmpty)
        #expect(pad.feed([], 0, 200, momentum: .began) == nil)
        #expect(pad.feed([], 0, 200, momentum: .changed) == nil)
    }

    @Test func aSidewaysGestureNeverStepsThatIsForTheTabs() {
        let pad = Trackpad()
        #expect(pad.gesture(Array(repeating: (30, 2), count: 20)).isEmpty)
        #expect(pad.gesture(Array(repeating: (-30, -2), count: 20)).isEmpty)
    }

    @Test func aDiagonalGestureIsIgnored() {
        let pad = Trackpad()
        #expect(pad.gesture(Array(repeating: (20, 20), count: 10)).isEmpty)
        #expect(pad.gesture(Array(repeating: (20, 30), count: 10)).isEmpty)
    }

    @Test func aGestureThatStartsSidewaysStaysIgnoredEvenIfItTurnsVertical() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, 20, 0) == nil)
        for _ in 0..<10 { #expect(pad.feed(.changed, 0, 60) == nil) }
    }

    @Test func aClearlyVerticalGestureWithALittleDriftStillSteps() {
        let pad = Trackpad()
        #expect(pad.gesture([(8, 30), (8, 30)]) == [.down])
        #expect(pad.gesture([(-10, -30), (-10, -30)]) == [.up])
    }

    @Test func aMouseWheelNeverSteps() {
        let pad = Trackpad()
        for _ in 0..<10 { #expect(pad.feed([], 0, 100) == nil) }
    }

    @Test func aGestureWithoutABeginIsIgnored() {
        let pad = Trackpad()
        for _ in 0..<5 { #expect(pad.feed(.changed, 0, 60) == nil) }
        #expect(pad.feed(.ended) == nil)
    }

    @Test func aCancelledGestureStopsCounting() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, 0, 30) == nil)
        #expect(pad.feed(.cancelled) == nil)
        #expect(pad.feed(.changed, 0, 60) == nil)
    }

    @Test func theTouchesOfAGestureThatHasNotStartedMovingDoNothing() {
        let pad = Trackpad()
        #expect(pad.feed(.mayBegin) == nil)
        #expect(pad.feed(.stationary) == nil)
        #expect(pad.feed(.began, 0, 60) == .down)
    }

    // MARK: sensitivity

    @Test func eachSensitivityHasItsOwnDistanceAndAMoreSensitiveOneNeedsLess() {
        #expect(SwipeSensitivity.high.distance < SwipeSensitivity.medium.distance)
        #expect(SwipeSensitivity.medium.distance < SwipeSensitivity.low.distance)
        // Longer than the distance that decides which way a gesture goes, or a step could come before the direction.
        #expect(SwipeSensitivity.high.distance > NotchSwipeRecognizer.lockDistance)
    }

    @Test func aGestureStepsAtExactlyTheDistanceOfItsSensitivityAndNotBefore() {
        for sensitivity in SwipeSensitivity.allCases {
            let distance = sensitivity.distance
            let pad = Trackpad()
            pad.sensitivity = sensitivity
            #expect(pad.feed(.began) == nil)
            #expect(pad.feed(.changed, 0, distance - 1) == nil, "\(sensitivity)")
            #expect(pad.feed(.changed, 0, 1) == .down, "\(sensitivity)")
        }
    }

    @Test func aLongSwipeStepsAtEverySensitivityAndAShortOneOnlyAtTheHighest() {
        let longest = SwipeSensitivity.low.distance
        let shortest = SwipeSensitivity.high.distance
        for sensitivity in SwipeSensitivity.allCases {
            let pad = Trackpad()
            pad.sensitivity = sensitivity
            #expect(pad.gesture([(0, longest)]) == [.down], "\(sensitivity)")
        }
        for (sensitivity, steps) in [(SwipeSensitivity.high, 1), (.medium, 0), (.low, 0)] {
            let pad = Trackpad()
            pad.sensitivity = sensitivity
            #expect(pad.gesture([(0, shortest)]).count == steps, "\(sensitivity)")
        }
    }

    @Test func theSensitivityOfTheGestureThatStepsIsTheOneGivenAtThatMoment() {
        let pad = Trackpad()
        pad.sensitivity = .low
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, 0, 30) == nil)
        pad.sensitivity = .high
        #expect(pad.feed(.changed, 0, 1) == .down)
    }

    @Test func mediumIsTheDefaultAndTheNamesAreWhatIsStored() {
        #expect(InterfaceSettings.swipeSensitivity.defaultValue == .medium)
        #expect(SwipeSensitivity.allCases.map(\.rawValue) == ["low", "medium", "high"])
    }

    // MARK: where the gesture starts

    @Test func aGestureThatBeginsOffTheNotchIsIgnoredWholly() {
        let pad = Trackpad()
        pad.onNotch = false
        #expect(pad.gesture(Array(repeating: (0, 30), count: 10)).isEmpty)
    }

    @Test func aGestureThatBeganOffTheNotchStaysIgnoredWhenThePointerGetsOntoIt() {
        let pad = Trackpad()
        pad.onNotch = false
        #expect(pad.feed(.began) == nil)
        pad.onNotch = true
        for _ in 0..<10 { #expect(pad.feed(.changed, 0, 30) == nil) }
    }

    @Test func aGestureThatBeganOnTheNotchGoesOnWhenThePointerLeavesIt() {
        let pad = Trackpad()
        #expect(pad.feed(.began) == nil)
        #expect(pad.feed(.changed, 0, 20) == nil)
        pad.onNotch = false
        #expect(pad.feed(.changed, 0, 30) == .down)
    }

    @Test func theNextGestureOnTheNotchCountsAfterOneThatBeganOffIt() {
        let pad = Trackpad()
        pad.onNotch = false
        #expect(pad.gesture([(0, 60)]).isEmpty)
        pad.onNotch = true
        #expect(pad.gesture([(0, 60)]) == [.down])
    }

    // MARK: what a step does

    @Test func aSwipeDownOpensTheCollapsedNotchAndAnUpwardOneClosesTheOpenNotch() {
        for state in [NotchState.closed, .compact] {
            #expect(Step.down.action(state: state) == .open, "\(state)")
            #expect(Step.up.action(state: state) == nil, "\(state)")
        }
        for state in [NotchState.open(nil), .open("a")] {
            #expect(Step.up.action(state: state) == .close, "\(state)")
            #expect(Step.down.action(state: state) == nil, "\(state)")
        }
    }

    @Test func aToastIsLeftAlone() {
        #expect(Step.down.action(state: .toast) == nil)
        #expect(Step.up.action(state: .toast) == nil)
    }

    @Test func aNotchThatSomethingKeepsOpenIsNeverClosedByASwipeButStillOpens() {
        for state in [NotchState.open(nil), .open("a")] {
            #expect(Step.up.action(state: state, keptOpen: true) == nil, "\(state)")
            #expect(Step.up.action(state: state, keptOpen: false) == .close, "\(state)")
        }
        #expect(Step.down.action(state: .closed, keptOpen: true) == .open)
        #expect(Step.down.action(state: .compact, keptOpen: true) == .open)
    }
}

private final class SwipeModule: FeatureModule {
    let descriptor: ModuleDescriptor
    private let acceptsKeyboard: Bool
    init(_ id: ModuleID, order: Int, acceptsKeyboard: Bool = false) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: true, order: order)
        self.acceptsKeyboard = acceptsKeyboard
    }
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: descriptor.displayName, systemImage: "circle", acceptsKeyboard: acceptsKeyboard,
            content: AnyView(EmptyView())
        )
    }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

/// The window controller turns scroll events nobody used into a notch that opens or closes. The panel is never shown and
/// no event is posted: the controller is called directly with a trackpad's phases and deltas, and the pointer is "over
/// the notch" through the model, which is what the real pointer moves set.
@Suite struct NotchOpenSwipeTests {
    final class Felt {
        var haptics: [Haptic] = []
    }

    let harness = RegistryHarness([SwipeModule("a", order: 1), SwipeModule("b", order: 2)])
    let felt = Felt()

    /// `sensitivity` is what the controller reads from the setting at each gesture; nil is off.
    func makeController(sensitivity: @escaping () -> SwipeSensitivity? = { .medium }) async -> NotchWindowController {
        await Self.makeController(harness: harness, felt: felt, sensitivity: sensitivity)
    }

    static func makeController(
        harness: RegistryHarness, felt: Felt, sensitivity: @escaping () -> SwipeSensitivity? = { .medium }
    ) async -> NotchWindowController {
        await harness.registry.bootstrap()
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 663.5, auxiliaryTopRightWidth: 663.5, menuBarHeight: 32
        )
        return NotchWindowController(
            displayID: 1, screen: screen, config: NotchLayoutConfig(), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities,
            delays: { (.milliseconds(150), .milliseconds(300)) },
            captureHiding: { .never },
            swipesBetweenTabs: { true },
            systemAllowsSwipe: { true },
            swipeToOpen: sensitivity,
            feel: { [felt] in felt.haptics.append($0) }
        )
    }

    /// One gesture of `dy` points (positive: fingers down), with momentum after it, as a trackpad sends it.
    func swipe(_ controller: NotchWindowController, dy: CGFloat, dx: CGFloat = 0, natural: Bool = true) {
        Self.swipe(controller, dy: dy, dx: dx, natural: natural)
    }

    static func swipe(_ controller: NotchWindowController, dy: CGFloat, dx: CGFloat = 0, natural: Bool = true) {
        controller.handleScroll(phase: .began, momentumPhase: [], deltaX: 0, deltaY: 0, naturalScrolling: natural)
        for _ in 0..<5 {
            controller.handleScroll(phase: .changed, momentumPhase: [], deltaX: dx / 5, deltaY: dy / 5, naturalScrolling: natural)
        }
        controller.handleScroll(phase: .ended, momentumPhase: [], deltaX: 0, deltaY: 0, naturalScrolling: natural)
        controller.handleScroll(phase: [], momentumPhase: .began, deltaX: dx, deltaY: dy, naturalScrolling: natural)
        for _ in 0..<5 { controller.handleScroll(phase: [], momentumPhase: .changed, deltaX: dx, deltaY: dy, naturalScrolling: natural) }
        controller.handleScroll(phase: [], momentumPhase: .ended, deltaX: 0, deltaY: 0, naturalScrolling: natural)
    }

    @Test func aSwipeDownOverTheCollapsedNotchOpensItOnItsFirstTabAndMomentumDoesNotCloseItAgain() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.pointerEntered()
        swipe(controller, dy: 200)
        #expect(controller.model.state == .open("a"))
    }

    @Test func aSwipeDownOpensItOnTheLastTabUsed() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "b")
        controller.model.close()
        controller.model.pointerEntered()
        swipe(controller, dy: 200)
        #expect(controller.model.state == .open("b"))
    }

    @Test func aSwipeUpOverTheOpenNotchClosesItAndAnotherSwipeUpDoesNothingMore() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "a")
        controller.model.pointerEntered()
        swipe(controller, dy: -200)
        #expect(controller.model.state == .closed)
        swipe(controller, dy: -200)
        #expect(controller.model.state == .closed)
    }

    @Test func aSwipeTheOtherWayDoesNothing() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.pointerEntered()
        swipe(controller, dy: -200)
        #expect(controller.model.state == .closed)
        controller.model.open(tab: "a")
        swipe(controller, dy: 200)
        #expect(controller.model.state == .open("a"))
    }

    @Test func aToastIsNotClosedByASwipe() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.showToast(AnyView(EmptyView()), duration: .seconds(5))
        controller.model.pointerEntered()
        swipe(controller, dy: -200)
        swipe(controller, dy: 200)
        #expect(controller.model.state == .toast)
    }

    @Test func theNotchFollowsASwipeThroughAFullOpenAndCloseAndOpenAgain() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.pointerEntered()
        swipe(controller, dy: 120)
        #expect(controller.model.state == .open("a"))
        swipe(controller, dy: -120)
        #expect(controller.model.state == .closed)
        swipe(controller, dy: 120)
        #expect(controller.model.state == .open("a"))
    }

    // MARK: where the pointer is

    @Test func nothingHappensWhenThePointerIsNotOverTheNotch() async {
        let controller = await makeController()
        defer { controller.close() }
        swipe(controller, dy: 200)
        #expect(controller.model.state == .closed)
        controller.model.open(tab: "a")
        swipe(controller, dy: -200)
        #expect(controller.model.state == .open("a"))
    }

    @Test func aBubbleBesideTheNotchOrTheListUnderItIsNotTheNotch() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.bubblesEntered()
        swipe(controller, dy: 200)
        #expect(controller.model.state == .closed)
        controller.model.listEntered()
        swipe(controller, dy: 200)
        #expect(controller.model.state == .closed)
    }

    @Test func aGestureThatBeganOutsideDoesNotOpenTheNotchWhenThePointerReachesIt() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.handleScroll(phase: .began, momentumPhase: [], deltaX: 0, deltaY: 0)
        controller.model.pointerEntered()
        for _ in 0..<10 { controller.handleScroll(phase: .changed, momentumPhase: [], deltaX: 0, deltaY: 20) }
        #expect(controller.model.state == .closed)
    }

    @Test func theNotchTheGestureBeganOnStillCountsWhenThePointerDriftsOutOfIt() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.pointerEntered()
        controller.handleScroll(phase: .began, momentumPhase: [], deltaX: 0, deltaY: 0)
        controller.model.pointerExited()
        for _ in 0..<5 { controller.handleScroll(phase: .changed, momentumPhase: [], deltaX: 0, deltaY: 20) }
        #expect(controller.model.state == .open("a"))
    }

    // MARK: setting

    @Test func switchedOffASwipeDoesNothingAndBackOnItWorksAgain() async {
        var allowed: SwipeSensitivity?
        let controller = await makeController { allowed }
        defer { controller.close() }
        controller.model.pointerEntered()
        swipe(controller, dy: 200)
        #expect(controller.model.state == .closed)
        allowed = .medium
        // The closure was captured: `allowed` is read at each event through the same variable.
        swipe(controller, dy: 200)
        #expect(controller.model.state == .open("a"))
    }

    @Test func theSensitivityDecidesHowFarASwipeHasToGo() async {
        for (sensitivity, opens) in [(SwipeSensitivity.high, true), (.medium, false), (.low, false)] {
            let controller = await makeController { sensitivity }
            controller.model.pointerEntered()
            swipe(controller, dy: SwipeSensitivity.high.distance + 4)
            #expect((controller.model.state == .open("a")) == opens, "\(sensitivity)")
            controller.close()
        }
    }

    // MARK: direction

    @Test func withNaturalScrollingOffTheFingersGoingDownIsAnUpwardScrollAndStillOpensTheNotch() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.pointerEntered()
        // Without natural scrolling a scroll delta is the content's: fingers down moves it up, a negative delta.
        swipe(controller, dy: -200, natural: false)
        #expect(controller.model.state == .open("a"))
        swipe(controller, dy: 200, natural: false)
        #expect(controller.model.state == .closed)
    }

    @Test func withNaturalScrollingOnTheFingersAndTheDeltaAgree() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.pointerEntered()
        swipe(controller, dy: -200, natural: true)
        #expect(controller.model.state == .closed)
        swipe(controller, dy: 200, natural: true)
        #expect(controller.model.state == .open("a"))
    }

    // MARK: next to the tab swipe

    @Test func aSidewaysSwipeStillChangesTabsAndANeverOpensOrClosesAnything() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "a")
        controller.model.pointerEntered()
        swipe(controller, dy: 0, dx: -200)
        #expect(controller.model.state == .open("b"))
        swipe(controller, dy: 0, dx: 200)
        #expect(controller.model.state == .open("a"))
    }

    @Test func aVerticalSwipeNeverChangesTheTab() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "a")
        controller.model.pointerEntered()
        swipe(controller, dy: 200)
        #expect(controller.model.state == .open("a"))
    }

    @Test func tabSwipesWorkWithSwipingToOpenSwitchedOff() async {
        let controller = await makeController { nil }
        defer { controller.close() }
        controller.model.open(tab: "a")
        swipe(controller, dy: 0, dx: -200)
        #expect(controller.model.state == .open("b"))
    }

    // MARK: haptics

    @Test func openingAndClosingBySwipeEachFeelOneLevelChange() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.pointerEntered()
        swipe(controller, dy: 200)
        #expect(felt.haptics == [.levelChange])
        swipe(controller, dy: -200)
        #expect(felt.haptics == [.levelChange, .levelChange])
    }

    @Test func aTabSwitchBySwipeFeelsOneAlignment() async {
        let controller = await makeController()
        defer { controller.close() }
        controller.model.open(tab: "a")
        swipe(controller, dy: 0, dx: -200)
        #expect(felt.haptics == [.alignment])
    }

    @Test func nothingIsFeltWhenNothingHappens() async {
        let controller = await makeController()
        defer { controller.close() }
        // Off the notch, the wrong way, at the end of the tab bar, a toast, a short swipe, momentum alone.
        swipe(controller, dy: 200)
        controller.model.pointerEntered()
        swipe(controller, dy: -200)
        controller.model.open(tab: "b")
        swipe(controller, dy: 0, dx: -200)
        controller.model.showToast(AnyView(EmptyView()), duration: .seconds(5))
        swipe(controller, dy: -200)
        controller.model.close()
        swipe(controller, dy: 10)
        controller.handleScroll(phase: [], momentumPhase: .changed, deltaX: 0, deltaY: 300)
        #expect(felt.haptics.isEmpty)
    }
}

/// A swipe is not a click: what keeps the notch open for a module keeps it open here too.
@Suite struct NotchSwipeKeptOpenTests {
    let harness = RegistryHarness([SwipeModule("a", order: 1), SwipeModule("b", order: 2)])
    let felt = NotchOpenSwipeTests.Felt()

    func openNotchUnderThePointer() async -> NotchWindowController {
        let controller = await NotchOpenSwipeTests.makeController(harness: harness, felt: felt)
        controller.model.open(tab: "a")
        controller.model.pointerEntered()
        return controller
    }

    @Test func aPinnedNotchStaysOpenForASwipeUpAndNothingIsFelt() async {
        let controller = await openNotchUnderThePointer()
        defer { controller.close() }
        controller.model.isPinned = true
        NotchOpenSwipeTests.swipe(controller, dy: -200)
        #expect(controller.model.state == .open("a"))
        #expect(controller.model.isPinned)
        #expect(felt.haptics.isEmpty)
    }

    @Test func aSwipeUpClosesItOnceNothingPinsItAnymore() async {
        let controller = await openNotchUnderThePointer()
        defer { controller.close() }
        controller.model.isPinned = true
        NotchOpenSwipeTests.swipe(controller, dy: -200)
        controller.model.isPinned = false
        NotchOpenSwipeTests.swipe(controller, dy: -200)
        #expect(controller.model.state == .closed)
        #expect(felt.haptics == [.levelChange])
    }

    @Test func aDragInProgressKeepsTheNotchOpenAndIsNotEnded() async {
        let controller = await openNotchUnderThePointer()
        defer { controller.close() }
        controller.model.setDragging(true)
        NotchOpenSwipeTests.swipe(controller, dy: -200)
        #expect(controller.model.state == .open("a"))
        #expect(controller.model.isDragging)
        #expect(felt.haptics.isEmpty)
    }

    @Test func aNotchThatIsBothPinnedAndDraggedStaysOpenToo() async {
        let controller = await openNotchUnderThePointer()
        defer { controller.close() }
        controller.model.isPinned = true
        controller.model.setDragging(true)
        NotchOpenSwipeTests.swipe(controller, dy: -200)
        #expect(controller.model.state == .open("a"))
        #expect(controller.model.isPinned && controller.model.isDragging)
    }

    @Test func aSwipeUpStillClosesAnUnpinnedNotchNotBeingDragged() async {
        let controller = await openNotchUnderThePointer()
        defer { controller.close() }
        NotchOpenSwipeTests.swipe(controller, dy: -200)
        #expect(controller.model.state == .closed)
        #expect(felt.haptics == [.levelChange])
    }

    @Test func theTabSwipeIsNotHeldByThePinBecauseItClosesNothing() async {
        let controller = await openNotchUnderThePointer()
        defer { controller.close() }
        controller.model.isPinned = true
        NotchOpenSwipeTests.swipe(controller, dy: 0, dx: -200)
        #expect(controller.model.state == .open("b"))
        #expect(controller.model.isPinned)
    }
}

/// Opening with a swipe is a hover-class gesture: the pointer is already on the notch and nothing was clicked, so a
/// tab that takes the keyboard does not take it from the app in front. A click, the shortcut or the tab bar still do.
@Suite struct NotchSwipeKeyboardTests {
    let harness = RegistryHarness([SwipeModule("k", order: 1, acceptsKeyboard: true), SwipeModule("a", order: 2)])
    let felt = NotchOpenSwipeTests.Felt()

    func focuses(_ model: NotchViewModel) -> Bool {
        NotchKeyboardPolicy.focusesKeyboard(
            state: model.state, tabUnderToast: model.tabUnderToast, tabs: harness.registry.tabs, onPurpose: model.isOpenedOnPurpose
        )
    }

    func wants(_ model: NotchViewModel) -> Bool {
        NotchKeyboardPolicy.wantsKeyboard(state: model.state, tabUnderToast: model.tabUnderToast, tabs: harness.registry.tabs)
    }

    @Test func aSwipeOpenOnAKeyboardTabDoesNotTakeTheKeyboard() async {
        let controller = await NotchOpenSwipeTests.makeController(harness: harness, felt: felt)
        defer { controller.close() }
        controller.model.pointerEntered()
        NotchOpenSwipeTests.swipe(controller, dy: 200)
        #expect(controller.model.state == .open("k"))
        #expect(!controller.model.isOpenedOnPurpose)
        // The tab can still take the keyboard when clicked into; it just does not grab it.
        #expect(wants(controller.model))
        #expect(!focuses(controller.model))
        #expect(felt.haptics == [.levelChange])
    }

    @Test func aClickTheShortcutAndTheTabBarStillOpenOnPurposeAndTakeTheKeyboard() async {
        let controller = await NotchOpenSwipeTests.makeController(harness: harness, felt: felt)
        defer { controller.close() }
        let model = controller.model
        model.click()
        #expect(model.isOpenedOnPurpose && focuses(model))
        model.close()
        model.toggle()
        #expect(model.isOpenedOnPurpose && focuses(model))
        model.close()
        model.open(tab: "k")
        #expect(model.isOpenedOnPurpose && focuses(model))
        model.close()
        #expect(model.openTab(of: "k"))
        #expect(model.isOpenedOnPurpose)
    }

    @Test func theModelCanOpenWithHoverSemanticsOnAnyTab() async {
        let controller = await NotchOpenSwipeTests.makeController(harness: harness, felt: felt)
        defer { controller.close() }
        let model = controller.model
        model.open(tab: "k", onPurpose: false)
        #expect(model.state == .open("k") && !model.isOpenedOnPurpose && !focuses(model))
        model.open(tab: "k", onPurpose: true)
        #expect(model.isOpenedOnPurpose && focuses(model))
    }
}
