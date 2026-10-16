import AppKit
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// The menu bar with two separators: ‹ (hidden zone) and ‹‹ (always-hidden zone) further left, the MyNotch icon on the right.
@Suite struct MenuBarSectionsTests {
    private final class Rig {
        let hider: MenuBarHider
        let separator = FakeSeparator()
        let scheduler = ManualScheduler()
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        /// What the closure given to the hider answers: the pointer is on a menu bar.
        var pointerOnBar = false

        init(section: Bool = true, startingUp: Bool = false, startCollapsed: Bool = false, quietFor grace: Duration = .zero) {
            separator.hasAlwaysHiddenSection = section
            settings.set(startCollapsed, for: MenuBarHiderSettings.startCollapsed)
            var pointer: () -> Bool = { false }
            hider = MenuBarHider(settings: settings, scheduler: scheduler, isPointerOnMenuBar: { pointer() })
            pointer = { [unowned self] in pointerOnBar }
            hider.attach(separator, quietFor: grace, startingUp: startingUp)
        }
    }

    private let long = MenuBarHider.collapsedLength
    private let normal = MenuBarHider.expandedLength

    // MARK: the sections

    @Test func startsWithBothZonesShownAndBothSeparatorsAtTheirNormalLength() {
        let rig = Rig()
        #expect(rig.hider.level == .all)
        #expect(rig.separator.length == normal)
        #expect(rig.separator.alwaysHiddenLength == normal)
    }

    @Test func collapsingMakesBothSeparatorsLong() {
        let rig = Rig()
        #expect(rig.hider.toggle())
        #expect(rig.hider.level == .collapsed)
        #expect(rig.separator.length == long)
        #expect(rig.separator.alwaysHiddenLength == long)
    }

    @Test func aPlainClickFromHiddenShowsTheHiddenZoneAndLeavesTheAlwaysHiddenOneAway() {
        let rig = Rig()
        rig.hider.collapse()
        #expect(rig.hider.toggle())
        #expect(rig.hider.level == .expanded)
        #expect(rig.separator.length == normal)
        #expect(rig.separator.alwaysHiddenLength == long)
        #expect(rig.separator.alwaysLengths == [normal, long])   // attach, then collapse; expanding never touched it
    }

    @Test func aPlainClickWhileAnythingShowsHidesEverything() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.expand()
        #expect(rig.hider.toggle())
        #expect(rig.hider.level == .collapsed)
        rig.hider.toggleAll()
        #expect(rig.hider.level == .all)
        #expect(rig.hider.toggle())
        #expect(rig.hider.level == .collapsed)
        #expect(rig.separator.length == long)
    }

    @Test func anOptionClickShowsEverythingAndAnotherOnePutsTheAlwaysHiddenZoneAway() {
        let rig = Rig()
        rig.hider.collapse()
        #expect(rig.hider.toggleAll())
        #expect(rig.hider.level == .all)
        #expect(rig.separator.length == normal)
        #expect(rig.separator.alwaysHiddenLength == normal)
        #expect(rig.hider.toggleAll())
        #expect(rig.hider.level == .expanded)
        #expect(rig.separator.length == normal)
        #expect(rig.separator.alwaysHiddenLength == long)
        #expect(rig.hider.toggleAll())
        #expect(rig.hider.level == .all)
    }

    @Test func anOptionClickFromTheHiddenZoneShownShowsTheRest() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.expand()
        #expect(rig.hider.toggleAll())
        #expect(rig.hider.level == .all)
        #expect(rig.separator.alwaysHiddenLength == normal)
    }

    @Test func withoutASecondSeparatorAnOptionClickIsAPlainClickAndNothingTouchesIt() {
        let rig = Rig(section: false)
        #expect(rig.hider.toggleAll())
        #expect(rig.hider.level == .collapsed)
        #expect(rig.hider.toggleAll())
        #expect(rig.hider.level == .expanded)
        #expect(rig.separator.lengths == [normal, long, normal])
        #expect(rig.separator.alwaysLengths.isEmpty)
    }

    @Test func showingEverythingForTheQuitGivesBothSeparatorsTheirNormalLengthAtOnce() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.revealAll()
        #expect(rig.hider.level == .all)
        #expect(rig.separator.length == normal)
        #expect(rig.separator.alwaysHiddenLength == normal)
    }

    @Test func detachingGivesBackBothSeparators() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.detach()
        #expect(rig.separator.length == normal)
        #expect(rig.separator.alwaysHiddenLength == normal)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func theAutoCollapseHidesBothZones() {
        let rig = Rig()
        rig.scheduler.advance(by: .seconds(10))
        #expect(rig.hider.level == .collapsed)
        #expect(rig.separator.alwaysHiddenLength == long)
    }

    @Test func revealOnHoverShowsOnlyTheHiddenZone() {
        let rig = Rig()
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.collapse()
        rig.hider.pointerMoved(inMenuBar: true)
        #expect(rig.hider.level == .expanded)
        #expect(rig.separator.alwaysHiddenLength == long)
        rig.hider.pointerMoved(inMenuBar: false)
        rig.scheduler.advance(by: MenuBarHider.hoverLinger)
        #expect(rig.hider.level == .collapsed)
    }

    // MARK: never hiding the way back, with two separators

    @Test func refusesToHideWhileTheAlwaysHiddenSeparatorIsRightOfTheFirstOne() {
        let rig = Rig()
        rig.separator.dragAlwaysHiddenRightOfSeparator()
        #expect(!rig.hider.toggle())
        #expect(rig.hider.level == .all)
        #expect(rig.separator.length == normal)
        #expect(rig.separator.alwaysHiddenLength == normal)
        rig.separator.alwaysHiddenFrame = CGRect(x: 1_460, y: 1_093, width: 24, height: 24)
        #expect(rig.hider.toggle())
        #expect(rig.separator.alwaysHiddenLength == long)
    }

    @Test func refusesToHideWhileTheAlwaysHiddenSeparatorIsRightOfTheIconToo() {
        let rig = Rig()
        rig.separator.alwaysHiddenFrame = CGRect(x: 1_600, y: 1_093, width: 24, height: 24)
        #expect(!rig.hider.collapse())
        #expect(!rig.hider.toggleAll())
        #expect(rig.hider.level == .all)
    }

    @Test func refusesToHideWhileTheAlwaysHiddenSeparatorHasNoWindowOrIsOffTheBar() {
        let rig = Rig()
        rig.separator.alwaysHiddenFrame = nil
        #expect(!rig.hider.collapse())
        rig.separator.alwaysHiddenFrame = CGRect(x: -9_000, y: 1_093, width: 24, height: 24)
        #expect(!rig.hider.collapse())
        #expect(rig.separator.alwaysLengths == [normal])   // only the attach
    }

    @Test func theFirstSeparatorStillHasToBeLeftOfTheIcon() {
        let rig = Rig()
        rig.separator.dragSeparatorRightOfToggle()
        #expect(!rig.hider.collapse())
        #expect(!rig.hider.toggleAll())
        #expect(rig.hider.level == .all)
    }

    @Test func withoutASectionTheAlwaysHiddenFrameIsNotLookedAt() {
        let rig = Rig(section: false)
        rig.separator.alwaysHiddenFrame = nil
        #expect(rig.hider.collapse())
    }

    @Test func puttingTheAlwaysHiddenZoneAwayIsRefusedWhenTheOrderIsWrong() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.toggleAll()
        rig.separator.dragAlwaysHiddenRightOfSeparator()
        #expect(!rig.hider.toggleAll())
        #expect(rig.hider.level == .all)
        #expect(rig.separator.alwaysHiddenLength == normal)
    }

    @Test func hidingFromTheHiddenZoneShownOnlyJudgesTheFirstSeparatorBecauseTheSecondIsLong() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.expand()
        // ‹‹ is long and its window reaches off the left of the screen, so its frame says nothing.
        rig.separator.alwaysHiddenFrame = CGRect(x: -8_500, y: 1_093, width: 10_000, height: 24)
        #expect(rig.hider.collapse())
        #expect(rig.hider.level == .collapsed)
    }

    @Test func theIconLeavingTheBarWhileOnlyTheAlwaysHiddenSeparatorIsLongShowsEverything() {
        let rig = Rig()
        var forced = 0
        rig.hider.onForcedExpand = { forced += 1 }
        rig.hider.collapse()
        rig.hider.expand()
        rig.separator.pushToggleOffScreen()
        rig.hider.layoutChanged()
        rig.scheduler.advance(by: MenuBarHider.settleDelay)
        #expect(rig.hider.level == .all)
        #expect(rig.separator.length == normal)
        #expect(rig.separator.alwaysHiddenLength == normal)
        #expect(forced == 1)
    }

    @Test func aLayoutChangeWithTheIconStillOnTheBarChangesNothingInTheHiddenZoneShown() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.expand()
        rig.hider.layoutChanged()
        rig.scheduler.advance(by: .seconds(1))
        #expect(rig.hider.level == .expanded)
    }

    @Test func aLayoutChangeWhileEverythingShowsSchedulesNothing() {
        let rig = Rig()
        rig.hider.layoutChanged()
        #expect(rig.scheduler.pendingCount == 1)   // only the auto-collapse
    }

    @Test func withoutASectionTheHiddenZoneShownIsNotWatched() {
        let rig = Rig(section: false)
        rig.hider.collapse()
        rig.hider.expand()
        rig.hider.layoutChanged()
        #expect(rig.scheduler.pendingCount == 1)   // only the auto-collapse
    }

    @Test func showingEverythingDropsAPendingCheckBecauseNothingIsLongAnyMore() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.layoutChanged()
        rig.hider.toggleAll()
        rig.separator.pushToggleOffScreen()
        rig.scheduler.advance(by: MenuBarHider.settleDelay)
        #expect(rig.hider.level == .all)
        #expect(rig.scheduler.pendingCount == 1)   // only the auto-collapse
    }

    // MARK: the section appearing and going away

    @Test func aSectionThatAppearsShowsEverythingAndHoldsBackTheAutoCollapseWhileIconsAreArranged() {
        let rig = Rig(section: false)
        rig.hider.collapse()
        rig.separator.hasAlwaysHiddenSection = true
        rig.hider.alwaysHiddenSectionChanged(quietFor: .seconds(60))
        #expect(rig.hider.level == .all)
        #expect(rig.separator.length == normal)
        rig.scheduler.advance(by: .seconds(59))
        #expect(rig.hider.level == .all)
        rig.scheduler.advance(by: .seconds(1))
        #expect(rig.hider.level == .collapsed)
        #expect(rig.separator.alwaysHiddenLength == long)
    }

    @Test func aSectionThatGoesAwayLeavesTheHiderWorking() {
        let rig = Rig()
        rig.hider.collapse()
        rig.separator.hasAlwaysHiddenSection = false
        rig.hider.alwaysHiddenSectionChanged()
        #expect(rig.hider.level == .collapsed)
        let lengths = rig.separator.alwaysLengths
        #expect(rig.hider.toggle())
        #expect(rig.hider.level == .expanded)
        #expect(rig.hider.toggle())
        #expect(rig.separator.alwaysLengths == lengths)
    }

    // MARK: hiding at start

    @Test func hidingAtStartCollapsesOnceTheWindowsHaveSettledAndNotBefore() {
        let rig = Rig(section: false, startingUp: true, startCollapsed: true)
        rig.scheduler.advance(by: MenuBarHider.startDelay - .milliseconds(1))
        #expect(rig.hider.level == .all)
        rig.scheduler.advance(by: .milliseconds(1))
        #expect(rig.hider.level == .collapsed)
    }

    @Test func hidingAtStartWorksWhenTheAutoCollapseIsNever() {
        let rig = Rig(section: false, startingUp: true, startCollapsed: true)
        rig.settings.set(0, for: MenuBarHiderSettings.autoCollapseSeconds)
        rig.hider.attach(rig.separator, startingUp: true)
        rig.scheduler.advance(by: MenuBarHider.startDelay)
        #expect(rig.hider.level == .collapsed)
    }

    @Test func aLaunchWithoutTheSettingHidesNothingEarly() {
        let rig = Rig(section: false, startingUp: true)
        #expect(rig.scheduler.pendingCount == 1)   // only the auto-collapse
        rig.scheduler.advance(by: .seconds(9))
        #expect(rig.hider.level == .all)
    }

    @Test func theSettingDoesNothingWhenTheHiderWasJustSwitchedOnBecauseTheUserIsArranging() {
        let rig = Rig(section: false, startingUp: true, startCollapsed: true, quietFor: .seconds(60))
        rig.scheduler.advance(by: .seconds(59))
        #expect(rig.hider.level == .all)
    }

    @Test func theSettingDoesNothingForAnAttachThatIsNotALaunch() {
        let rig = Rig(section: false, startingUp: false, startCollapsed: true)
        rig.scheduler.advance(by: MenuBarHider.startDelay)
        #expect(rig.hider.level == .all)
    }

    @Test func withTheSectionOnAndHidingAtStartOffOnlyTheAlwaysHiddenZoneGoesAway() {
        let rig = Rig(startingUp: true)
        rig.scheduler.advance(by: MenuBarHider.startDelay)
        #expect(rig.hider.level == .expanded)
        #expect(rig.separator.length == normal)
        #expect(rig.separator.alwaysHiddenLength == long)
        rig.scheduler.advance(by: .seconds(10))
        #expect(rig.hider.level == .collapsed)
    }

    @Test func aStartThatIsRefusedBecauseTheWindowsAreNotInPlaceYetIsTriedAgain() {
        let rig = Rig(section: false, startingUp: true, startCollapsed: true)
        rig.separator.toggleFrame = nil
        rig.scheduler.advance(by: MenuBarHider.startDelay)
        #expect(rig.hider.level == .all)
        rig.separator.toggleFrame = CGRect(x: 1_540, y: 1_093, width: 28, height: 24)
        rig.scheduler.advance(by: MenuBarHider.startRetryDelay)
        #expect(rig.hider.level == .collapsed)
    }

    @Test func aStartThatKeepsBeingRefusedGivesUpAfterThreeTries() {
        let rig = Rig(section: false, startingUp: true, startCollapsed: true)
        rig.settings.set(0, for: MenuBarHiderSettings.autoCollapseSeconds)
        rig.hider.attach(rig.separator, startingUp: true)
        rig.separator.toggleFrame = nil
        rig.scheduler.advance(by: MenuBarHider.startDelay + MenuBarHider.startRetryDelay * 2)
        #expect(rig.scheduler.pendingCount == 0)
        rig.separator.toggleFrame = CGRect(x: 1_540, y: 1_093, width: 28, height: 24)
        rig.scheduler.advance(by: .seconds(60))
        #expect(rig.hider.level == .all)
    }

    @Test func aClickBeforeTheStartKeepsTheUsersChoice() {
        let rig = Rig(section: false, startingUp: true, startCollapsed: true)
        rig.hider.collapse()
        rig.hider.expand()
        rig.scheduler.advance(by: MenuBarHider.startDelay)
        #expect(rig.hider.level == .expanded)   // the start did not collapse it again
    }

    // MARK: the auto-collapse waits for the pointer

    @Test func aDueAutoCollapseWaitsWhileThePointerIsOnTheMenuBar() {
        let rig = Rig(section: false)
        rig.pointerOnBar = true
        rig.scheduler.advance(by: .seconds(60))
        #expect(rig.hider.level == .all)
    }

    @Test func onceThePointerIsAwayACompleteNewCountStarts() {
        let rig = Rig(section: false)
        rig.pointerOnBar = true
        rig.scheduler.advance(by: .milliseconds(12_500))
        rig.pointerOnBar = false
        // It notices at the next look (13 s), and the count runs from there.
        rig.scheduler.advance(by: .milliseconds(10_400))
        #expect(rig.hider.level == .all)
        rig.scheduler.advance(by: .milliseconds(100))
        #expect(rig.hider.level == .collapsed)
    }

    @Test func thePointerComingBackDuringTheNewCountPausesItAgain() {
        let rig = Rig(section: false)
        rig.pointerOnBar = true
        rig.scheduler.advance(by: .seconds(11))
        rig.pointerOnBar = false
        rig.scheduler.advance(by: .seconds(1))     // the look that sees it away; a new 10 s count starts at 12 s
        rig.scheduler.advance(by: .seconds(9))
        rig.pointerOnBar = true
        rig.scheduler.advance(by: .seconds(5))
        #expect(rig.hider.level == .all)
        rig.pointerOnBar = false
        rig.scheduler.advance(by: .seconds(1))
        rig.scheduler.advance(by: .seconds(10))
        #expect(rig.hider.level == .collapsed)
    }

    @Test func thePointerOnTheBarDoesNotStopAHandCollapse() {
        let rig = Rig(section: false)
        rig.pointerOnBar = true
        #expect(rig.hider.toggle())
        #expect(rig.hider.level == .collapsed)
    }

    @Test func neverStaysNeverWithThePointerOnTheBar() {
        let rig = Rig(section: false)
        rig.settings.set(0, for: MenuBarHiderSettings.autoCollapseSeconds)
        rig.hider.settingsChanged()
        rig.pointerOnBar = true
        rig.scheduler.advance(by: .seconds(60))
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func aHandCollapseDropsTheWaitForThePointer() {
        let rig = Rig(section: false)
        rig.pointerOnBar = true
        rig.scheduler.advance(by: .seconds(11))
        rig.hider.collapse()
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func theEndOfTheGraceWaitsForThePointerToo() {
        let rig = Rig(section: false, quietFor: .seconds(60))
        rig.scheduler.advance(by: .seconds(30))
        rig.pointerOnBar = true
        rig.scheduler.advance(by: .seconds(30))
        #expect(rig.hider.level == .all)
        rig.pointerOnBar = false
        rig.scheduler.advance(by: .seconds(1))
        rig.scheduler.advance(by: .seconds(10))
        #expect(rig.hider.level == .collapsed)
    }

    @Test func theLingerAfterTheHoverRevealDoesNotWaitForThePointer() {
        let rig = Rig(section: false)
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.collapse()
        rig.hider.pointerMoved(inMenuBar: true)
        rig.hider.pointerMoved(inMenuBar: false)
        rig.pointerOnBar = true   // disagrees on purpose: the hover monitor said it left
        rig.scheduler.advance(by: MenuBarHider.hoverLinger)
        #expect(rig.hider.level == .collapsed)
    }
}
