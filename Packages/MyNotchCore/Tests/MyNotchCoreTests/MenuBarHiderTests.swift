import AppKit
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// Stands in for the status item, so nothing here touches the real menu bar.
private final class FakeSeparator: MenuBarSeparator {
    var length: CGFloat = 0 { didSet { lengths.append(length) } }
    var isLeftOfToggle = true
    private(set) var lengths: [CGFloat] = []
}

@Suite struct MenuBarHiderTests {
    private struct Rig {
        let hider: MenuBarHider
        let separator = FakeSeparator()
        let scheduler = ManualScheduler()
        let settings = SettingsStore(defaults: makeIsolatedDefaults())

        init() {
            hider = MenuBarHider(settings: settings, scheduler: scheduler)
            hider.attach(separator)
        }
    }

    private let collapsed = MenuBarHider.collapsedLength
    private let expanded = MenuBarHider.expandedLength

    // MARK: lengths

    @Test func collapsedPushesTheItemsOnItsLeftOffTheScreenAndExpandedIsNormal() {
        #expect(MenuBarHider.collapsedLength >= 10_000)
        #expect(MenuBarHider.expandedLength == NSStatusItem.variableLength)
    }

    @Test func attachingShowsEverythingAndLeavesTheSeparatorAtItsNormalLength() {
        let rig = Rig()
        #expect(rig.separator.length == expanded)
        #expect(!rig.hider.isCollapsed)
    }

    @Test func toggleCollapsesAndExpandsAgain() {
        let rig = Rig()
        #expect(rig.hider.toggle())
        #expect(rig.hider.isCollapsed)
        #expect(rig.separator.length == collapsed)
        #expect(rig.hider.toggle())
        #expect(!rig.hider.isCollapsed)
        #expect(rig.separator.length == expanded)
    }

    @Test func collapsingTwiceOrExpandingTwiceTouchesTheItemOnce() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.collapse()
        rig.hider.expand()
        rig.hider.expand()
        #expect(rig.separator.lengths == [expanded, collapsed, expanded])
    }

    @Test func doesNothingWithoutASeparator() {
        let hider = MenuBarHider(settings: SettingsStore(defaults: makeIsolatedDefaults()), scheduler: ManualScheduler())
        #expect(!hider.toggle())
        #expect(!hider.collapse())
        #expect(!hider.isCollapsed)
    }

    // MARK: never hiding the way back

    @Test func refusesToCollapseWhileTheSeparatorIsRightOfTheToggle() {
        let rig = Rig()
        rig.separator.isLeftOfToggle = false
        #expect(!rig.hider.toggle())
        #expect(!rig.hider.isCollapsed)
        #expect(rig.separator.length == expanded)
        rig.separator.isLeftOfToggle = true
        #expect(rig.hider.toggle())
        #expect(rig.separator.length == collapsed)
    }

    @Test func aRefusedAutoCollapseLeavesItExpandedAndDoesNotTryAgain() {
        let rig = Rig()
        rig.separator.isLeftOfToggle = false
        rig.scheduler.advance(by: .seconds(10))
        #expect(!rig.hider.isCollapsed)
        #expect(rig.scheduler.pendingCount == 0)
    }

    // MARK: auto-collapse

    @Test func collapsesByItselfTenSecondsAfterItWasShown() {
        let rig = Rig()
        rig.scheduler.advance(by: .milliseconds(9_900))
        #expect(!rig.hider.isCollapsed)
        rig.scheduler.advance(by: .milliseconds(100))
        #expect(rig.hider.isCollapsed)
        #expect(rig.separator.length == collapsed)
    }

    @Test func expandingStartsTheCountAgain() {
        let rig = Rig()
        rig.hider.collapse()
        rig.scheduler.advance(by: .seconds(30))
        rig.hider.expand()
        rig.scheduler.advance(by: .seconds(9))
        #expect(!rig.hider.isCollapsed)
        rig.scheduler.advance(by: .seconds(1))
        #expect(rig.hider.isCollapsed)
    }

    @Test func collapsingByHandCancelsThePendingAutoCollapse() {
        let rig = Rig()
        rig.hider.collapse()
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func zeroSecondsMeansNeverCollapseByItself() {
        let rig = Rig()
        rig.settings.set(0, for: MenuBarHiderSettings.autoCollapseSeconds)
        rig.hider.settingsChanged()
        rig.scheduler.advance(by: .seconds(3_600))
        #expect(!rig.hider.isCollapsed)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func aChangedDelayCountsFromTheChange() {
        let rig = Rig()
        rig.scheduler.advance(by: .seconds(8))
        rig.settings.set(3, for: MenuBarHiderSettings.autoCollapseSeconds)
        rig.hider.settingsChanged()
        rig.scheduler.advance(by: .seconds(2))
        #expect(!rig.hider.isCollapsed)
        rig.scheduler.advance(by: .seconds(1))
        #expect(rig.hider.isCollapsed)
    }

    @Test func aDelayAddedAfterNeverStartsCounting() {
        let rig = Rig()
        rig.settings.set(0, for: MenuBarHiderSettings.autoCollapseSeconds)
        rig.hider.settingsChanged()
        rig.settings.set(5, for: MenuBarHiderSettings.autoCollapseSeconds)
        rig.hider.settingsChanged()
        rig.scheduler.advance(by: .seconds(5))
        #expect(rig.hider.isCollapsed)
    }

    @Test func changingTheDelayWhileCollapsedSchedulesNothing() {
        let rig = Rig()
        rig.hider.collapse()
        rig.settings.set(3, for: MenuBarHiderSettings.autoCollapseSeconds)
        rig.hider.settingsChanged()
        #expect(rig.scheduler.pendingCount == 0)
        #expect(rig.hider.isCollapsed)
    }

    // MARK: detach and replace

    @Test func detachingGivesTheMenuBarBackAndStopsTheTimer() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.expand()
        rig.hider.collapse()
        rig.hider.detach()
        #expect(rig.separator.length == expanded)
        #expect(!rig.hider.isCollapsed)
        #expect(rig.scheduler.pendingCount == 0)
        #expect(!rig.hider.toggle())
    }

    @Test func aNewSeparatorReplacesTheOldOneWhichIsNotTouchedAgain() {
        let rig = Rig()
        let second = FakeSeparator()
        rig.hider.collapse()
        rig.hider.attach(second)
        let before = rig.separator.lengths
        #expect(second.length == expanded)
        #expect(!rig.hider.isCollapsed)
        rig.hider.toggle()
        #expect(second.length == collapsed)
        #expect(rig.separator.lengths == before)
    }

    // MARK: revealing on hover

    @Test func theMenuBarDoesNothingWhileRevealOnHoverIsOff() {
        let rig = Rig()
        rig.hider.collapse()
        rig.hider.pointerMoved(inMenuBar: true)
        #expect(rig.hider.isCollapsed)
        rig.hider.pointerMoved(inMenuBar: false)
        #expect(rig.hider.isCollapsed)
    }

    @Test func thePointerOnTheMenuBarRevealsAndLeavingHidesAfterAMoment() {
        let rig = Rig()
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.collapse()
        rig.hider.pointerMoved(inMenuBar: true)
        #expect(!rig.hider.isCollapsed)
        #expect(rig.separator.length == expanded)
        rig.scheduler.advance(by: .seconds(60))
        #expect(!rig.hider.isCollapsed)
        rig.hider.pointerMoved(inMenuBar: false)
        rig.scheduler.advance(by: MenuBarHider.hoverLinger - .milliseconds(1))
        #expect(!rig.hider.isCollapsed)
        rig.scheduler.advance(by: .milliseconds(1))
        #expect(rig.hider.isCollapsed)
    }

    @Test func comingBackWithinTheMomentKeepsItRevealed() {
        let rig = Rig()
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.collapse()
        rig.hider.pointerMoved(inMenuBar: true)
        rig.hider.pointerMoved(inMenuBar: false)
        rig.scheduler.advance(by: .milliseconds(500))
        rig.hider.pointerMoved(inMenuBar: true)
        rig.scheduler.advance(by: .seconds(60))
        #expect(!rig.hider.isCollapsed)
    }

    @Test func aClickWhileRevealedByHoverCollapsesAndCancelsTheHoverTimer() {
        let rig = Rig()
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.collapse()
        rig.hider.pointerMoved(inMenuBar: true)
        #expect(rig.hider.toggle())
        #expect(rig.hider.isCollapsed)
        rig.hider.pointerMoved(inMenuBar: false)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func collapsingByHandWithThePointerOnTheBarStaysCollapsedUntilItLeavesAndComesBack() {
        let rig = Rig()
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.pointerMoved(inMenuBar: true)
        rig.hider.collapse()
        rig.hider.pointerMoved(inMenuBar: true)
        #expect(rig.hider.isCollapsed)
        rig.hider.pointerMoved(inMenuBar: false)
        rig.hider.pointerMoved(inMenuBar: true)
        #expect(!rig.hider.isCollapsed)
    }

    @Test func aHoverThatMovesWhileAlreadyExpandedByHandChangesNothing() {
        let rig = Rig()
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.pointerMoved(inMenuBar: true)
        rig.hider.pointerMoved(inMenuBar: false)
        rig.scheduler.advance(by: MenuBarHider.hoverLinger)
        #expect(!rig.hider.isCollapsed)
        rig.scheduler.advance(by: .seconds(10))
        #expect(rig.hider.isCollapsed)
    }

    @Test func turningRevealOnHoverOffWhileRevealedHandsOverToTheAutoCollapse() {
        let rig = Rig()
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.collapse()
        rig.hider.pointerMoved(inMenuBar: true)
        rig.settings.set(false, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.settingsChanged()
        rig.scheduler.advance(by: .seconds(10))
        #expect(rig.hider.isCollapsed)
    }

    @Test func aRefusedHoverCollapseLeavesItExpandedWithoutRetrying() {
        let rig = Rig()
        rig.settings.set(true, for: MenuBarHiderSettings.revealOnHover)
        rig.hider.collapse()
        rig.hider.pointerMoved(inMenuBar: true)
        rig.separator.isLeftOfToggle = false
        rig.hider.pointerMoved(inMenuBar: false)
        rig.scheduler.advance(by: MenuBarHider.hoverLinger)
        #expect(!rig.hider.isCollapsed)
        #expect(rig.scheduler.pendingCount == 0)
    }
}
