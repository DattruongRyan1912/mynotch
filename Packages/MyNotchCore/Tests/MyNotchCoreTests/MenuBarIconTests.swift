import Testing
@testable import MyNotchCore

@Suite struct MenuBarIconTests {
    private func action(
        leftMouseUp: Bool = true, control: Bool = false, age: Double = 0.01, onButton: Bool = true
    ) -> MenuBarIcon.Action {
        MenuBarIcon.action(isLeftMouseUp: leftMouseUp, hasControl: control, eventAge: age, isOnButton: onButton)
    }

    @Test func aPlainLeftClickOnTheIconTogglesTheHiddenIcons() {
        #expect(action() == .toggleHiddenIcons)
    }

    @Test func everyOtherActivationOpensTheMenu() {
        #expect(action(leftMouseUp: false) == .openMenu)                    // a right click, a key, an accessibility press
        #expect(action(control: true) == .openMenu)                         // a control-click
        #expect(action(age: 0.6) == .openMenu)                              // an old click the action was not caused by
        #expect(action(onButton: false) == .openMenu)                       // a click somewhere else
    }

    @Test func noEventAtAllOpensTheMenu() {
        #expect(MenuBarIcon.action(isLeftMouseUp: false, hasControl: false, eventAge: .infinity, isOnButton: false) == .openMenu)
    }

    // MARK: the icon's tooltip

    @Test func theTooltipExplainsTheClicksWhileTheHiderIsOn() {
        #expect(MenuBarIcon.toolTip(permissionNudge: nil, hiderIsOn: true) == "Bấm: hiện/ẩn icon. Chuột phải: menu.")
    }

    @Test func theTooltipIsEmptyWithoutAHiderOrANudge() {
        #expect(MenuBarIcon.toolTip(permissionNudge: nil, hiderIsOn: false) == nil)
    }

    @Test func theNudgeKeepsItsOwnLineAndTheClicksFollow() {
        #expect(MenuBarIcon.toolTip(permissionNudge: "Thiếu 2 quyền…", hiderIsOn: false) == "MyNotch: Thiếu 2 quyền…")
        #expect(MenuBarIcon.toolTip(permissionNudge: "Thiếu 2 quyền…", hiderIsOn: true)
            == "MyNotch: Thiếu 2 quyền…\nBấm: hiện/ẩn icon. Chuột phải: menu.")
    }
}
