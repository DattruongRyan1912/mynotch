import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct MenuBarHiderSettingsTests {
    @Test func offByDefaultWithATenSecondDelayAndNoHover() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(store.value(MenuBarHiderSettings.enabled) == false)
        #expect(store.value(MenuBarHiderSettings.autoCollapseSeconds) == 10)
        #expect(store.value(MenuBarHiderSettings.revealOnHover) == false)
        #expect(store.value(MenuBarHiderSettings.alwaysHiddenSection) == false)
        #expect(store.value(MenuBarHiderSettings.startCollapsed) == false)
    }

    @Test func choicesSurviveARelaunch() {
        let defaults = makeIsolatedDefaults()
        let first = SettingsStore(defaults: defaults)
        first.set(true, for: MenuBarHiderSettings.enabled)
        first.set(25, for: MenuBarHiderSettings.autoCollapseSeconds)
        first.set(true, for: MenuBarHiderSettings.revealOnHover)
        first.set(true, for: MenuBarHiderSettings.alwaysHiddenSection)
        first.set(true, for: MenuBarHiderSettings.startCollapsed)
        let second = SettingsStore(defaults: defaults)
        #expect(second.value(MenuBarHiderSettings.enabled))
        #expect(second.value(MenuBarHiderSettings.autoCollapseSeconds) == 25)
        #expect(second.value(MenuBarHiderSettings.revealOnHover))
        #expect(second.value(MenuBarHiderSettings.alwaysHiddenSection))
        #expect(second.value(MenuBarHiderSettings.startCollapsed))
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
        #expect(MenuBarHiderSettings.alwaysHiddenSection.name == "app.menuBarHider.alwaysHiddenEnabled")
        #expect(MenuBarHiderSettings.startCollapsed.name == "app.menuBarHider.startCollapsed")
    }

    @Test func thePickerOffersNeverAndFiveToThirtySecondsAndIncludesTheDefault() {
        #expect(MenuBarHiderSettings.autoCollapseChoices == [0, 5, 10, 15, 30])
        #expect(MenuBarHiderSettings.autoCollapseChoices.contains(MenuBarHiderSettings.autoCollapseSeconds.defaultValue))
    }
}
