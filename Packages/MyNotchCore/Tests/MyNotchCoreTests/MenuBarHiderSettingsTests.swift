import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct MenuBarHiderSettingsTests {
    @Test func offByDefaultWithATenSecondDelayAndNoHover() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(store.value(MenuBarHiderSettings.enabled) == false)
        #expect(store.value(MenuBarHiderSettings.autoCollapseSeconds) == 10)
        #expect(store.value(MenuBarHiderSettings.revealOnHover) == false)
    }

    @Test func choicesSurviveARelaunch() {
        let defaults = makeIsolatedDefaults()
        let first = SettingsStore(defaults: defaults)
        first.set(true, for: MenuBarHiderSettings.enabled)
        first.set(25, for: MenuBarHiderSettings.autoCollapseSeconds)
        first.set(true, for: MenuBarHiderSettings.revealOnHover)
        let second = SettingsStore(defaults: defaults)
        #expect(second.value(MenuBarHiderSettings.enabled))
        #expect(second.value(MenuBarHiderSettings.autoCollapseSeconds) == 25)
        #expect(second.value(MenuBarHiderSettings.revealOnHover))
    }

    @Test func theDelayStaysBetweenNeverAndFiveMinutes() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        store.set(-3, for: MenuBarHiderSettings.autoCollapseSeconds)
        #expect(store.value(MenuBarHiderSettings.autoCollapseSeconds) == 0)
        store.set(100_000, for: MenuBarHiderSettings.autoCollapseSeconds)
        #expect(store.value(MenuBarHiderSettings.autoCollapseSeconds) == 300)
    }

    @Test func theKeyNamesAreFixedSoARenameCannotResetAnyonesChoice() {
        #expect(MenuBarHiderSettings.enabled.name == "app.menuBarHider.enabled")
        #expect(MenuBarHiderSettings.autoCollapseSeconds.name == "app.menuBarHider.autoCollapseSeconds")
        #expect(MenuBarHiderSettings.revealOnHover.name == "app.menuBarHider.revealOnHover")
    }
}
