import AppKit
import Testing
@testable import NotchUI

/// The hand-back every window of MyNotch that keeps the keyboard uses. Nothing is shown and no key status moves: the
/// AppKit steps are replaced by a recorder, and the check by a value.
@Suite struct KeyboardHandBackTests {
    typealias Step = KeyboardReturn.Step

    func makeWindow() -> NSPanel {
        NSPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 40), styleMask: [.borderless], backing: .buffered, defer: true)
    }

    // MARK: Whether the keyboard really is back

    @Test func theKeyboardIsBackWhenNoWindowOfMyNotchHasItAndTheAppThatWasInFrontStillIs() {
        #expect(KeyboardHandBack.keyboardIsWith(expected: 100, frontmost: 100, own: 1, hasKeyWindow: false))
    }

    @Test func aWindowOfMyNotchStillHavingTheKeyboardMeansItIsNotBack() {
        #expect(!KeyboardHandBack.keyboardIsWith(expected: 100, frontmost: 100, own: 1, hasKeyWindow: true))
    }

    @Test func myNotchBeingInFrontMeansThereIsNoOtherAppToGiveItTo() {
        #expect(!KeyboardHandBack.keyboardIsWith(expected: 1, frontmost: 1, own: 1, hasKeyWindow: false))
        #expect(!KeyboardHandBack.keyboardIsWith(expected: nil, frontmost: 1, own: 1, hasKeyWindow: false))
        #expect(!KeyboardHandBack.keyboardIsWith(expected: 100, frontmost: 1, own: 1, hasKeyWindow: false))
    }

    @Test func anotherAppTakingTheFrontInTheMeantimeIsNotTheAppTheKeyboardWasGivenTo() {
        #expect(!KeyboardHandBack.keyboardIsWith(expected: 100, frontmost: 200, own: 1, hasKeyWindow: false))
    }

    @Test func noAppInFrontMeansNowhereToGiveItTo() {
        #expect(!KeyboardHandBack.keyboardIsWith(expected: 100, frontmost: nil, own: 1, hasKeyWindow: false))
        #expect(!KeyboardHandBack.keyboardIsWith(expected: nil, frontmost: nil, own: 1, hasKeyWindow: false))
    }

    @Test func withoutAnExpectedAppAnyOtherAppInFrontWillDo() {
        #expect(KeyboardHandBack.keyboardIsWith(expected: nil, frontmost: 200, own: 1, hasKeyWindow: false))
    }

    // MARK: The steps

    @Test func theStrategysStepsRunInOrderAndTheAnswerIsTheCheck() {
        for (isBack, strategy, expected) in [
            (true, KeyboardReturn.sinkPanel, [Step.showSink, .makeSinkKey, .hideSink]),
            (false, .sinkPanel, [.showSink, .makeSinkKey, .hideSink]),
            (true, .sinkAndActivate, [.showSink, .makeSinkKey, .hideSink, .activateFrontApp]),
            (true, .orderOutIn, [.orderNotchOut, .orderNotchIn]),
        ] {
            var performed: [Step] = []
            let handBack = KeyboardHandBack(strategy: { strategy }, perform: { step, _, _ in performed.append(step) }, check: { _ in isBack })

            let result = handBack.returnKeyboard(from: makeWindow(), to: nil, frontIsOtherApp: true)

            #expect(performed == expected, "\(strategy)")
            #expect(result == isBack, "\(strategy)")
        }
    }

    @Test func reactivatingTheAppInFrontIsLeftOutWhenMyNotchItselfIsInFront() {
        var performed: [Step] = []
        let handBack = KeyboardHandBack(strategy: { .sinkAndActivate }, perform: { step, _, _ in performed.append(step) }, check: { _ in false })

        #expect(!handBack.returnKeyboard(from: makeWindow(), to: nil, frontIsOtherApp: false))
        #expect(performed == [.showSink, .makeSinkKey, .hideSink])
    }

    @Test func theCheckIsGivenTheAppTheKeyboardWasMeantFor() {
        var asked: [NSRunningApplication?] = []
        let handBack = KeyboardHandBack(strategy: { .sinkPanel }, perform: { _, _, _ in }, check: { asked.append($0); return true })
        let app = NSRunningApplication.current

        _ = handBack.returnKeyboard(from: makeWindow(), to: app, frontIsOtherApp: true)
        #expect(asked.count == 1)
        #expect(asked.first??.processIdentifier == app.processIdentifier)
    }

    @Test func theAppInFrontIsAnotherAppOnlyWhenItsProcessIsNotMyNotch() {
        #expect(KeyboardHandBack.isOtherApp(pid: 100, own: 1))
        #expect(!KeyboardHandBack.isOtherApp(pid: 1, own: 1))
        #expect(!KeyboardHandBack.isOtherApp(pid: nil, own: 1))
    }

    // MARK: The hidden panel

    @Test func theHiddenPanelIsAOnePointClearWindowThatCanOnlyTakeKeyStatus() {
        let sink = KeySinkPanel()
        #expect(sink.frame.size == CGSize(width: 1, height: 1))
        #expect(sink.styleMask.contains(.nonactivatingPanel))
        #expect(sink.canBecomeKey)
        #expect(!sink.canBecomeMain)
        #expect(sink.ignoresMouseEvents)
        #expect(!sink.isOpaque)
        #expect(!sink.hidesOnDeactivate)
        #expect(!sink.isVisible)
    }
}
