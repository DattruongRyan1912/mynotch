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
}
