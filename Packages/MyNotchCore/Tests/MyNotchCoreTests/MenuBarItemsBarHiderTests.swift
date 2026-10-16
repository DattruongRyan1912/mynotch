import CoreGraphics
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// What the bar needs of the hider: the layout the sections have right now, a way back to a level, and word of a change.
@Suite struct MenuBarItemsBarHiderTests {
    private struct Rig {
        let hider: MenuBarHider
        let separator = FakeSeparator()
        let scheduler = ManualScheduler()
        let settings = SettingsStore(defaults: makeIsolatedDefaults())

        init(always: Bool = false) {
            hider = MenuBarHider(settings: settings, scheduler: scheduler)
            separator.hasAlwaysHiddenSection = always
            hider.attach(separator)
        }
    }

    // MARK: layout

    @Test func withoutASeparatorThereIsNoLayout() {
        let hider = MenuBarHider(settings: SettingsStore(defaults: makeIsolatedDefaults()), scheduler: ManualScheduler())
        #expect(hider.layout == nil)
    }

    @Test func theLayoutCarriesTheDisplaysAndTheSeparatorWhileItHasItsNormalLength() {
        let rig = Rig()
        #expect(rig.hider.layout == MenuBarLayout(screens: rig.separator.screens, hiddenSeparator: rig.separator.separatorFrame))
    }

    @Test func collapsedTheSeparatorsWindowSaysNothing() {
        let rig = Rig()
        rig.hider.collapse()
        #expect(rig.hider.layout == MenuBarLayout(screens: rig.separator.screens))
    }

    @Test func theAlwaysHiddenSeparatorCountsOnlyWhileItsZoneIsShown() {
        let rig = Rig(always: true)
        #expect(rig.hider.level == .all)
        #expect(rig.hider.layout?.alwaysHiddenSeparator == rig.separator.alwaysHiddenFrame)
        rig.hider.collapse()
        rig.hider.expand()
        #expect(rig.hider.level == .expanded)
        #expect(rig.hider.layout?.hiddenSeparator == rig.separator.separatorFrame)
        #expect(rig.hider.layout?.alwaysHiddenSeparator == nil)
    }

    @Test func aMissingWindowLeavesTheSeparatorOutOfTheLayout() {
        let rig = Rig()
        rig.separator.separatorFrame = nil
        #expect(rig.hider.layout?.hiddenSeparator == nil)
    }

    // MARK: restoring a level

    @Test func theHiderGoesBackToACollapsedLevel() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.revealAll()
        #expect(rig.hider.level == .all)
        #expect(rig.hider.restore(to: .collapsed))
        #expect(rig.hider.isCollapsed)
        #expect(rig.separator.length == MenuBarHider.collapsedLength)
    }

    @Test func restoringACollapsedLevelIsRefusedWhenTheSeparatorsAreOutOfOrder() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.revealAll()
        rig.separator.dragSeparatorRightOfToggle()
        #expect(!rig.hider.restore(to: .collapsed))
        #expect(rig.hider.level == .all)
    }

    @Test func theHiderGoesBackToTheHiddenZoneOnly() {
        let rig = Rig(always: true)
        rig.hider.collapse()
        rig.hider.expand()
        rig.hider.revealAll()
        #expect(rig.hider.restore(to: .expanded))
        #expect(rig.hider.level == .expanded)
    }

    @Test func restoringTheLevelItIsAtIsASuccessThatChangesNothing() {
        let rig = Rig()
        #expect(rig.hider.restore(to: .all))
        #expect(rig.separator.lengths == [MenuBarHider.expandedLength])
    }

    // MARK: word of a change

    @Test func everyChangeOfLevelIsReportedOnce() {
        let rig = Rig(always: true)
        var seen: [MenuBarHider.Level] = []
        rig.hider.onLevelChanged = { seen.append(rig.hider.level) }
        rig.hider.collapse()
        rig.hider.collapse()
        rig.hider.expand()
        rig.hider.revealAll()
        rig.hider.revealAll()
        #expect(seen == [.collapsed, .expanded, .all])
    }

    @Test func aRevealByThePointerIsReportedToo() {
        let rig = Rig()
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.collapse()
        var calls = 0
        rig.hider.onLevelChanged = { calls += 1 }
        rig.hider.pointerMoved(inMenuBar: true)
        #expect(calls == 1)
    }
}
