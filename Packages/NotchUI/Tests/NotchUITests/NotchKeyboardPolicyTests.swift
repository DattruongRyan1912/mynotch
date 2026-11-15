import MyNotchCore
import SwiftUI
import Testing
@testable import NotchUI

@Suite struct NotchKeyboardPolicyTests {
    let tabs = [
        NotchTab(id: "battery", title: "Battery", systemImage: "circle", content: AnyView(EmptyView())),
        NotchTab(id: "clipboard", title: "Clipboard", systemImage: "circle", acceptsKeyboard: true, content: AnyView(EmptyView())),
    ]

    func wantsKeyboard(_ state: NotchState, under covered: ModuleID? = nil) -> Bool {
        NotchKeyboardPolicy.wantsKeyboard(state: state, tabUnderToast: covered, tabs: tabs)
    }

    func focusesKeyboard(_ state: NotchState, under covered: ModuleID? = nil, onPurpose: Bool) -> Bool {
        NotchKeyboardPolicy.focusesKeyboard(state: state, tabUnderToast: covered, tabs: tabs, onPurpose: onPurpose)
    }

    @Test func collapsedNotchesAndToastsOverNoKeyboardTabNeverTakeTheKeyboard() {
        #expect(!wantsKeyboard(.closed))
        #expect(!wantsKeyboard(.compact))
        #expect(!wantsKeyboard(.toast))
        #expect(!wantsKeyboard(.toast, under: "battery"))
        #expect(!focusesKeyboard(.toast, onPurpose: true))
    }

    @Test func onlyAnOpenTabThatAcceptsKeyboardTakesIt() {
        #expect(wantsKeyboard(.open("clipboard")))
        #expect(!wantsKeyboard(.open("battery")))
        #expect(!wantsKeyboard(.open(nil)))
        #expect(!wantsKeyboard(.open("missing")))
    }

    @Test func aToastOverAKeyboardTabKeepsTheKeyboard() {
        #expect(wantsKeyboard(.toast, under: "clipboard"))
        #expect(focusesKeyboard(.toast, under: "clipboard", onPurpose: true))
    }

    @Test func onlyANotchOpenedOnPurposeFocusesTheKeyboard() {
        #expect(focusesKeyboard(.open("clipboard"), onPurpose: true))
        #expect(!focusesKeyboard(.open("clipboard"), onPurpose: false))
        #expect(!focusesKeyboard(.toast, under: "clipboard", onPurpose: false))
        #expect(!focusesKeyboard(.open("battery"), onPurpose: true))
    }

    func plan(
        wants: Bool, focuses: Bool = false, wasFocused: Bool = false, isKey: Bool = false, isVisible: Bool = true
    ) -> NotchKeyboardPolicy.PanelKeyPlan {
        NotchKeyboardPolicy.panelKeyPlan(wants: wants, focuses: focuses, wasFocused: wasFocused, isKey: isKey, isVisible: isVisible)
    }

    @Test func leavingAKeyboardTabHandsTheKeyboardBackAtOnce() {
        let leaving = plan(wants: false, isKey: true)
        #expect(leaving.handBack)
        // Not allowed any more, so giving key status up is never mistaken for the user clicking elsewhere.
        #expect(!leaving.allowsKeyStatus)
    }

    @Test func aHiddenPanelHasNothingToHandBack() {
        #expect(!plan(wants: false, isKey: true, isVisible: false).handBack)
    }

    @Test func aPanelThatIsNotKeyHasNothingToHandBack() {
        let plain = plan(wants: false, isKey: false)
        #expect(!plain.handBack)
        #expect(!plain.allowsKeyStatus)
    }

    @Test func aKeyboardTabKeepsTheKeyboardAndNeverHandsBack() {
        let typing = plan(wants: true, isKey: true)
        #expect(typing.allowsKeyStatus)
        #expect(!typing.handBack)
    }

    @Test func aToastOverTheKeyboardTabKeepsTheKeyboard() {
        #expect(!plan(wants: wantsKeyboard(.toast, under: "clipboard"), isKey: true).handBack)
        #expect(plan(wants: wantsKeyboard(.toast, under: "battery"), isKey: true).handBack)
    }

    @Test func thePanelBecomesKeyOnlyWhenFocusStartsAndItIsOnScreen() {
        #expect(plan(wants: true, focuses: true).makeKey)
        #expect(!plan(wants: true, focuses: true, wasFocused: true).makeKey)
        #expect(!plan(wants: true, focuses: true, isVisible: false).makeKey)
        #expect(!plan(wants: true, focuses: false).makeKey)
    }

    /// Replays the controller's loop (the panel is key after `makeKey`, not key after a hand-back) over a series of notch states.
    func replay(_ states: [NotchState], onPurpose: Bool = true) -> [(state: NotchState, plan: NotchKeyboardPolicy.PanelKeyPlan)] {
        var isKey = false
        var wasFocused = false
        return states.map { state in
            let focuses = focusesKeyboard(state, onPurpose: onPurpose)
            let result = NotchKeyboardPolicy.panelKeyPlan(
                wants: wantsKeyboard(state), focuses: focuses, wasFocused: wasFocused, isKey: isKey, isVisible: true
            )
            if result.makeKey { isKey = true }
            if result.handBack { isKey = false }
            wasFocused = focuses
            return (state, result)
        }
    }

    @Test func theKeyboardGoesBackExactlyOnceRightAfterLeavingAKeyboardTab() {
        let steps = replay([.open("battery"), .open("clipboard"), .open("clipboard"), .open("battery"), .open("battery")])
        #expect(steps.map(\.plan.makeKey) == [false, true, false, false, false])
        #expect(steps.map(\.plan.handBack) == [false, false, false, true, false])
    }

    @Test func everyVisitToAKeyboardTabIsHandedBackOnce() {
        let steps = replay([.open("clipboard"), .open("battery"), .open("clipboard"), .open("battery"), .open("clipboard"), .closed])
        #expect(steps.filter(\.plan.makeKey).count == 3)
        #expect(steps.filter(\.plan.handBack).count == 3)
    }

    @Test func closingFromAKeyboardTabHandsBackWithoutAnyNotchSizeInTheDecision() {
        let steps = replay([.open("clipboard"), .closed, .closed])
        #expect(steps.map(\.plan.handBack) == [false, true, false])
    }
}
