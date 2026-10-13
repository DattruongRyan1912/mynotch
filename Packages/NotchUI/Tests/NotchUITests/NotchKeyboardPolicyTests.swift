import MyNotchCore
import SwiftUI
import Testing
@testable import NotchUI

@Suite struct NotchKeyboardPolicyTests {
    let tabs = [
        NotchTab(id: "battery", title: "Battery", systemImage: "circle", content: AnyView(EmptyView())),
        NotchTab(id: "clipboard", title: "Clipboard", systemImage: "circle", acceptsKeyboard: true, content: AnyView(EmptyView())),
    ]

    func wantsKeyboard(_ state: NotchState) -> Bool {
        NotchKeyboardPolicy.wantsKeyboard(state: state, tabs: tabs)
    }

    @Test func collapsedNotchesAndToastsNeverTakeTheKeyboard() {
        #expect(!wantsKeyboard(.closed))
        #expect(!wantsKeyboard(.compact))
        #expect(!wantsKeyboard(.toast))
    }

    @Test func onlyAnOpenTabThatAcceptsKeyboardTakesIt() {
        #expect(wantsKeyboard(.open("clipboard")))
        #expect(!wantsKeyboard(.open("battery")))
        #expect(!wantsKeyboard(.open(nil)))
        #expect(!wantsKeyboard(.open("missing")))
    }
}
