import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct MenuBarItemsBarSettingsTests {
    @Test func theBarIsOnUntilTheUserTurnsItOff() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(store.value(MenuBarHiderSettings.itemsBar))
    }

    @Test func theChoiceSurvivesARelaunch() {
        let defaults = makeIsolatedDefaults()
        let first = SettingsStore(defaults: defaults)
        first.set(false, for: MenuBarHiderSettings.itemsBar)
        #expect(SettingsStore(defaults: defaults).value(MenuBarHiderSettings.itemsBar) == false)
        first.set(true, for: MenuBarHiderSettings.itemsBar)
        #expect(SettingsStore(defaults: defaults).value(MenuBarHiderSettings.itemsBar))
    }

    @Test func theOtherHiderSettingsAreNotTouchedByIt() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        store.set(false, for: MenuBarHiderSettings.itemsBar)
        #expect(store.value(MenuBarHiderSettings.enabled) == false)
        #expect(store.value(MenuBarHiderSettings.autoCollapseSeconds) == 10)
    }
}
