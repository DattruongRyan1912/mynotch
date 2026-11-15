import Testing
@testable import MyNotchCore

/// What a click on the MyNotch icon or on ‹ does once the bar can take the place of expanding the hidden section, and the
/// setting that turns it on.
@Suite struct MenuBarItemsBarClickTests {
    private func action(
        leftMouseUp: Bool = true, control: Bool = false, option: Bool = false, age: Double = 0.01, onButton: Bool = true,
        bar: Bool = true
    ) -> MenuBarIcon.Action {
        MenuBarIcon.action(
            isLeftMouseUp: leftMouseUp, hasControl: control, hasOption: option, eventAge: age, isOnButton: onButton,
            barInsteadOfExpanding: bar
        )
    }

    // MARK: the icon

    @Test func aPlainClickOnTheIconOpensTheBarWhenItIsAvailable() {
        #expect(action() == .toggleBar)
    }

    @Test func anOptionClickKeepsTheOldBehaviourOfExpandingInPlace() {
        #expect(action(option: true) == .toggleAllIcons)
    }

    @Test func withoutTheBarEveryClickIsWhatItWas() {
        #expect(action(bar: false) == .toggleHiddenIcons)
        #expect(action(option: true, bar: false) == .toggleAllIcons)
    }

    @Test func theBarChangesNothingAboutTheMenu() {
        #expect(action(leftMouseUp: false) == .openMenu)
        #expect(action(control: true) == .openMenu)
        #expect(action(age: 0.6) == .openMenu)
        #expect(action(onButton: false) == .openMenu)
        #expect(action(leftMouseUp: false, option: true) == .openMenu)
    }

    @Test func theDefaultIsStillTheOldBehaviourForCallersThatDoNotKnowTheBar() {
        #expect(MenuBarIcon.action(isLeftMouseUp: true, hasControl: false, eventAge: 0, isOnButton: true) == .toggleHiddenIcons)
    }

    // MARK: the separator ‹

    @Test func aClickOnTheSeparatorFollowsTheSameRule() {
        #expect(MenuBarIcon.separatorAction(hasOption: false, barInsteadOfExpanding: true) == .toggleBar)
        #expect(MenuBarIcon.separatorAction(hasOption: true, barInsteadOfExpanding: true) == .toggleAllIcons)
        #expect(MenuBarIcon.separatorAction(hasOption: false, barInsteadOfExpanding: false) == .toggleHiddenIcons)
        #expect(MenuBarIcon.separatorAction(hasOption: true, barInsteadOfExpanding: false) == .toggleAllIcons)
    }

    // MARK: the tooltip

    @Test func theTooltipSaysWhatTheBarAndTheOptionClickDo() {
        #expect(MenuBarIcon.toolTip(permissionNudge: nil, hiderIsOn: true, barInsteadOfExpanding: true)
            == "Bấm: mở thanh icon ẩn. Giữ ⌥ khi bấm: hiện icon ngay trên menu bar. Chuột phải: menu.")
        #expect(MenuBarIcon.toolTip(permissionNudge: nil, hiderIsOn: true, alwaysHiddenSection: true, barInsteadOfExpanding: true)
            == "Bấm: mở thanh icon ẩn. Giữ ⌥ khi bấm: hiện icon ngay trên menu bar, cả icon luôn ẩn. Chuột phải: menu.")
        #expect(MenuBarIcon.toolTip(permissionNudge: nil, hiderIsOn: false, barInsteadOfExpanding: true) == nil)
    }

    // MARK: the setting

    @Test func theBarIsOnByDefault() {
        #expect(MenuBarHiderSettings.itemsBar.defaultValue == true)
        #expect(MenuBarHiderSettings.itemsBar.name == "app.menuBarHider.itemsBar")
    }
}
