import CoreGraphics
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// Stands in for Accessibility: a list of items, their frames as they are now, and what a press does.
final class FakeItemSource: MenuBarItemSource {
    var isTrusted = true
    var listed: [MenuBarItem] = []
    /// What `currentFrame(of:)` says when it differs from the listed frame.
    var frames: [String: CGRect] = [:]
    var results: [MenuBarItemAction: MenuBarItemActionResult] = [.press: .performed, .showMenu: .performed]
    private(set) var itemsCalls = 0
    private(set) var performed: [(action: MenuBarItemAction, id: String)] = []
    /// Called as an action is performed, to look at the world at that moment.
    var onPerform: (() -> Void)?

    func items() async -> [MenuBarItem] {
        itemsCalls += 1
        return listed
    }

    func currentFrame(of id: String) -> CGRect? {
        frames[id] ?? listed.first { $0.id == id }?.frame
    }

    func perform(_ action: MenuBarItemAction, on id: String) -> MenuBarItemActionResult {
        performed.append((action, id))
        onPerform?()
        return results[action] ?? .failed
    }
}

/// Stands in for the hider's sections.
final class FakeSections: MenuBarSectionControl {
    var level: MenuBarHider.Level = .collapsed
    private(set) var log: [String] = []
    var onReveal: (() -> Void)?

    func revealAll() {
        log.append("revealAll")
        level = .all
        onReveal?()
    }

    func restore(to level: MenuBarHider.Level) -> Bool {
        log.append("restore:\(level)")
        self.level = level
        return true
    }
}

final class FakeImages: MenuBarItemImageSource {
    var result: [String: CGImage] = [:]
    private(set) var asked: [[String]] = []

    func images(for items: [MenuBarItem]) async -> [String: CGImage] {
        asked.append(items.map(\.id))
        return result
    }
}

private func makeImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

@Suite struct MenuBarItemsBarTests {
    private static let notched = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117), barHeight: 38, notchGap: 764...964)

    /// One reachable item, one pushed off the screen, one under the notch and one without a frame.
    private static let onBar = item("onBar", x: 1_500)
    private static let parked = item("parked", x: -9_000)
    private static let notchHidden = item("notch", x: 800)
    private static let flat = MenuBarItem(
        id: "flat", pid: 4, ownerBundleID: nil, ownerName: "Flat", title: nil, details: nil, frame: .zero, order: 3
    )

    private static func item(_ id: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            id: id, pid: 9, ownerBundleID: "com.example.\(id)", ownerName: id.capitalized, title: nil, details: nil,
            frame: CGRect(x: x, y: 1_093, width: 24, height: 24), order: 0
        )
    }

    private final class Rig {
        let source = FakeItemSource()
        let sections = FakeSections()
        let images = FakeImages()
        let scheduler = ManualScheduler()
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        var pointerOnBar = false
        var layout = MenuBarLayout(screens: [MenuBarItemsBarTests.notched])
        private(set) var bar: MenuBarItemsBar!
        var openChanges: [Bool] = []
        var failures = 0

        init(withImages: Bool = false) {
            source.listed = [onBar, parked, notchHidden, flat]
            bar = MenuBarItemsBar(
                source: source, images: withImages ? images : nil, sections: sections, settings: settings, scheduler: scheduler,
                layout: { [unowned self] in layout }, isPointerOnBar: { [unowned self] in pointerOnBar }
            )
            bar.onOpenChanged = { [unowned self] in openChanges.append($0) }
            bar.onPressFailed = { [unowned self] in failures += 1 }
        }

        func open() async {
            bar.open()
            await bar.settled()
        }
    }

    // MARK: closed

    @Test func aClosedBarNeverTouchesAccessibilityOrTheScheduler() {
        let rig = Rig()
        rig.bar.itemsMayHaveChanged()
        rig.bar.itemsMayHaveChanged()
        rig.bar.settingsChanged()
        // Nothing is even scheduled: a timer that would find the bar closed later does not count.
        #expect(rig.scheduler.pendingCount == 0)
        rig.scheduler.advance(by: .seconds(120))
        #expect(rig.source.itemsCalls == 0)
        #expect(!rig.bar.isOpen)
    }

    @Test func aClosedBarHoldsNothing() {
        let rig = Rig()
        #expect(rig.bar.entries.isEmpty)
        #expect(rig.bar.images.isEmpty)
    }

    // MARK: opening

    @Test func openingListsTheItemsTheMenuBarCannotShowInMenuBarOrder() async {
        let rig = Rig()
        await rig.open()
        #expect(rig.bar.isOpen)
        #expect(rig.bar.phase == .ready)
        #expect(rig.bar.entries.map(\.id) == ["parked", "notch", "flat"])
        #expect(rig.bar.entries.map(\.reason) == [.offScreen, .underNotch, .zeroSize])
        #expect(rig.source.itemsCalls == 1)
        #expect(rig.openChanges == [true])
    }

    @Test func theBarIsLoadingUntilTheFirstListArrives() {
        let rig = Rig()
        rig.bar.open()
        #expect(rig.bar.phase == .loading)
        #expect(rig.bar.entries.isEmpty)
    }

    @Test func openingAgainWhileOpenDoesNothingMore() async {
        let rig = Rig()
        await rig.open()
        rig.bar.open()
        await rig.bar.settled()
        #expect(rig.source.itemsCalls == 1)
        #expect(rig.openChanges == [true])
    }

    @Test func everyOpeningReadsTheItemsAgain() async {
        let rig = Rig()
        await rig.open()
        rig.bar.close(.toggle)
        await rig.open()
        #expect(rig.source.itemsCalls == 2)
    }

    @Test func withoutAccessibilityNothingIsListedAndAccessibilityIsNotAsked() async {
        let rig = Rig()
        rig.source.isTrusted = false
        await rig.open()
        #expect(rig.bar.phase == .needsAccessibility)
        #expect(rig.bar.entries.isEmpty)
        #expect(rig.source.itemsCalls == 0)
    }

    @Test func aListWithNothingToShowIsReadyAndEmpty() async {
        let rig = Rig()
        rig.source.listed = [Self.onBar]
        await rig.open()
        #expect(rig.bar.phase == .ready)
        #expect(rig.bar.entries.isEmpty)
    }

    @Test func theListIsJudgedAgainstTheLayoutAsItIsWhenItArrives() async {
        let rig = Rig()
        rig.layout = MenuBarLayout(
            screens: [Self.notched], hiddenSeparator: CGRect(x: 1_300, y: 1_093, width: 24, height: 24)
        )
        rig.source.listed = [Self.item("shown", x: 1_000)]
        await rig.open()
        #expect(rig.bar.entries.map(\.reason) == [.hiddenSection])
    }

    // MARK: refreshing on events only

    @Test func eventsWhileOpenRefreshOnceAfterTheyStop() async {
        let rig = Rig()
        await rig.open()
        rig.bar.itemsMayHaveChanged()
        rig.scheduler.advance(by: .milliseconds(100))
        rig.bar.itemsMayHaveChanged()
        rig.scheduler.advance(by: .milliseconds(100))
        rig.bar.itemsMayHaveChanged()
        rig.scheduler.advance(by: MenuBarItemsBar.refreshDelay - .milliseconds(1))
        #expect(rig.source.itemsCalls == 1)
        rig.scheduler.advance(by: .milliseconds(1))
        await rig.bar.settled()
        #expect(rig.source.itemsCalls == 2)
    }

    @Test func aRefreshPicksUpWhatChanged() async {
        let rig = Rig()
        await rig.open()
        rig.source.listed.append(Self.item("late", x: -9_100))
        rig.bar.itemsMayHaveChanged()
        rig.scheduler.advance(by: MenuBarItemsBar.refreshDelay)
        await rig.bar.settled()
        #expect(rig.bar.entries.map(\.id) == ["late", "parked", "notch", "flat"])
    }

    @Test func idleWhileOpenSchedulesNothingButTheAutoClose() async {
        let rig = Rig()
        await rig.open()
        #expect(rig.scheduler.pendingCount == 1)
        rig.scheduler.advance(by: .seconds(9))
        #expect(rig.source.itemsCalls == 1)
    }

    @Test func closingDropsAPendingRefreshAndLaterEventsDoNothing() async {
        let rig = Rig()
        await rig.open()
        rig.bar.itemsMayHaveChanged()
        rig.bar.close(.toggle)
        #expect(rig.scheduler.pendingCount == 0)
        rig.bar.itemsMayHaveChanged()
        rig.scheduler.advance(by: .seconds(30))
        #expect(rig.source.itemsCalls == 1)
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func aListThatArrivesAfterClosingIsDropped() async {
        let rig = Rig()
        rig.bar.open()
        rig.bar.close(.toggle)
        await rig.bar.settled()
        #expect(rig.bar.entries.isEmpty)
    }

    // MARK: closing

    @Test func closingRecordsWhyAndEmptiesTheBar() async {
        let rig = Rig(withImages: true)
        rig.images.result = ["parked": makeImage()]
        await rig.open()
        #expect(!rig.bar.images.isEmpty)
        rig.bar.close(.escape)
        #expect(!rig.bar.isOpen)
        #expect(rig.bar.lastCloseReason == .escape)
        #expect(rig.bar.entries.isEmpty)
        #expect(rig.bar.images.isEmpty)
        #expect(rig.openChanges == [true, false])
    }

    @Test func closingAClosedBarIsANoOp() {
        let rig = Rig()
        rig.bar.close(.clickOutside)
        #expect(rig.openChanges.isEmpty)
        #expect(rig.bar.lastCloseReason == nil)
    }

    @Test func toggleOpensAndCloses() async {
        let rig = Rig()
        rig.bar.toggle()
        await rig.bar.settled()
        #expect(rig.bar.isOpen)
        rig.bar.toggle()
        #expect(!rig.bar.isOpen)
        #expect(rig.bar.lastCloseReason == .toggle)
    }

    // MARK: auto-close

    @Test func theBarClosesAfterTheAutoCollapseTime() async {
        let rig = Rig()
        await rig.open()
        rig.scheduler.advance(by: .seconds(9))
        #expect(rig.bar.isOpen)
        rig.scheduler.advance(by: .seconds(1))
        #expect(!rig.bar.isOpen)
        #expect(rig.bar.lastCloseReason == .timeout)
    }

    @Test func noAutoCollapseTimeKeepsTheBarOpen() async {
        let rig = Rig()
        rig.settings.set(0, for: MenuBarHiderSettings.autoCollapseSeconds)
        await rig.open()
        #expect(rig.scheduler.pendingCount == 0)
        rig.scheduler.advance(by: .seconds(600))
        #expect(rig.bar.isOpen)
    }

    @Test func thePointerOnTheBarHoldsTheCloseAndTheCountStartsOverWhenItLeaves() async {
        let rig = Rig()
        rig.pointerOnBar = true
        await rig.open()
        rig.scheduler.advance(by: .seconds(10))
        #expect(rig.bar.isOpen)
        rig.scheduler.advance(by: .seconds(5))
        #expect(rig.bar.isOpen)
        rig.pointerOnBar = false
        rig.scheduler.advance(by: MenuBarItemsBar.pointerRecheck)
        #expect(rig.bar.isOpen)
        rig.scheduler.advance(by: .seconds(9))
        #expect(rig.bar.isOpen)
        rig.scheduler.advance(by: .seconds(1))
        #expect(!rig.bar.isOpen)
    }

    @Test func aChangedDelayCountsFromTheChange() async {
        let rig = Rig()
        await rig.open()
        rig.scheduler.advance(by: .seconds(8))
        rig.settings.set(5, for: MenuBarHiderSettings.autoCollapseSeconds)
        rig.bar.settingsChanged()
        rig.scheduler.advance(by: .seconds(4))
        #expect(rig.bar.isOpen)
        rig.scheduler.advance(by: .seconds(1))
        #expect(!rig.bar.isOpen)
    }

    // MARK: item looks

    @Test func capturedImagesAreKeptByItemAndTheRestFallBackToTheAppIcon() async {
        let rig = Rig(withImages: true)
        let image = makeImage()
        rig.images.result = ["parked": image]
        await rig.open()
        #expect(rig.images.asked == [["parked", "notch", "flat"]])
        #expect(rig.bar.images["parked"] === image)
        #expect(rig.bar.images["notch"] == nil)
        #expect(rig.bar.entries.map(\.id) == ["parked", "notch", "flat"])
    }

    @Test func aFailedCaptureLeavesTheListWithTheirTooltips() async {
        let rig = Rig(withImages: true)
        rig.images.result = [:]
        await rig.open()
        #expect(rig.bar.images.isEmpty)
        #expect(rig.bar.entries.count == 3)
        #expect(rig.bar.entries.map(\.item.toolTip) == ["Parked", "Notch", "Flat"])
    }

    @Test func withoutACaptureSourceNothingIsCaptured() async {
        let rig = Rig()
        await rig.open()
        #expect(rig.images.asked.isEmpty)
        #expect(rig.bar.images.isEmpty)
    }

    @Test func nothingIsCapturedWhenThereIsNothingToShow() async {
        let rig = Rig(withImages: true)
        rig.source.listed = [Self.onBar]
        await rig.open()
        #expect(rig.images.asked.isEmpty)
    }

    // MARK: clicking an item

    @Test func theBarIsClosedBeforeTheItemIsPressed() async {
        let rig = Rig()
        await rig.open()
        var wasOpen: Bool?
        rig.source.onPerform = { wasOpen = rig.bar.isOpen }
        rig.bar.choose("notch")
        #expect(wasOpen == false)
        #expect(rig.bar.lastCloseReason == .itemChosen)
    }

    @Test func aClickPressesTheItem() async {
        let rig = Rig()
        await rig.open()
        rig.bar.choose("notch")
        #expect(rig.source.performed.map(\.action) == [.press])
        #expect(rig.source.performed.map(\.id) == ["notch"])
        #expect(rig.failures == 0)
    }

    @Test func aClickOnAnItemWithoutPressShowsItsMenuInstead() async {
        let rig = Rig()
        rig.source.results[.press] = .unsupported
        await rig.open()
        rig.bar.choose("notch")
        #expect(rig.source.performed.map(\.action) == [.press, .showMenu])
        #expect(rig.failures == 0)
    }

    @Test func aRightClickShowsTheMenuFirstAndFallsBackToPress() async {
        let rig = Rig()
        await rig.open()
        rig.bar.choose("notch", secondary: true)
        #expect(rig.source.performed.map(\.action) == [.showMenu])
        let again = Rig()
        again.source.results[.showMenu] = .unsupported
        await again.open()
        again.bar.choose("notch", secondary: true)
        #expect(again.source.performed.map(\.action) == [.showMenu, .press])
    }

    @Test func anItemThatSupportsNeitherIsReported() async {
        let rig = Rig()
        rig.source.results = [.press: .unsupported, .showMenu: .unsupported]
        await rig.open()
        rig.bar.choose("notch")
        #expect(rig.source.performed.map(\.action) == [.press, .showMenu])
        #expect(rig.failures == 1)
    }

    @Test func aFailureIsNotRetriedWithTheNextAction() async {
        let rig = Rig()
        rig.source.results = [.press: .failed, .showMenu: .performed]
        await rig.open()
        rig.bar.choose("notch")
        #expect(rig.source.performed.map(\.action) == [.press])
        #expect(rig.failures == 1)
    }

    @Test func choosingSomethingNotInTheBarDoesNothing() async {
        let rig = Rig()
        await rig.open()
        rig.bar.choose("nope")
        #expect(rig.bar.isOpen)
        #expect(rig.source.performed.isEmpty)
    }

    @Test func choosingOnAClosedBarDoesNothing() {
        let rig = Rig()
        rig.bar.choose("notch")
        #expect(rig.source.performed.isEmpty)
    }

    // MARK: the fallback: showing the hidden section for a moment

    private static let onScreenAgain = CGRect(x: 1_400, y: 1_093, width: 24, height: 24)

    @Test func anItemPushedOffTheScreenIsRevealedFirstAndPressedWhereItAppears() async {
        let rig = Rig()
        rig.sections.onReveal = { rig.source.frames["parked"] = Self.onScreenAgain }
        await rig.open()
        rig.bar.choose("parked")
        #expect(rig.sections.log == ["revealAll"])
        #expect(rig.source.performed.isEmpty)
        rig.scheduler.advance(by: MenuBarItemsBar.revealPoll)
        #expect(rig.source.performed.map(\.id) == ["parked"])
        #expect(rig.source.performed.map(\.action) == [.press])
    }

    @Test func theSectionsGoBackAfterAWhile() async {
        let rig = Rig()
        rig.sections.onReveal = { rig.source.frames["parked"] = Self.onScreenAgain }
        await rig.open()
        rig.bar.choose("parked")
        rig.scheduler.advance(by: MenuBarItemsBar.revealPoll)
        rig.scheduler.advance(by: MenuBarItemsBar.restoreDelay - .milliseconds(1))
        #expect(rig.sections.log == ["revealAll"])
        rig.scheduler.advance(by: .milliseconds(1))
        #expect(rig.sections.log == ["revealAll", "restore:collapsed"])
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func theSectionsAreLeftAloneIfTheUserChangedThemInTheMeantime() async {
        let rig = Rig()
        rig.sections.onReveal = { rig.source.frames["parked"] = Self.onScreenAgain }
        await rig.open()
        rig.bar.choose("parked")
        rig.scheduler.advance(by: MenuBarItemsBar.revealPoll)
        rig.sections.level = .collapsed
        rig.scheduler.advance(by: MenuBarItemsBar.restoreDelay)
        #expect(rig.sections.log == ["revealAll"])
    }

    @Test func anItemThatNeverAppearsIsPressedAnywayAfterTheWait() async {
        let rig = Rig()
        await rig.open()
        rig.bar.choose("parked")
        rig.scheduler.advance(by: MenuBarItemsBar.revealPoll * (MenuBarItemsBar.revealPolls - 1))
        #expect(rig.source.performed.isEmpty)
        rig.scheduler.advance(by: MenuBarItemsBar.revealPoll)
        #expect(rig.source.performed.map(\.id) == ["parked"])
    }

    @Test func anItemUnderTheNotchIsNeverRevealedBecauseShowingTheSectionCannotMoveIt() async {
        let rig = Rig()
        await rig.open()
        rig.bar.choose("notch")
        #expect(rig.sections.log.isEmpty)
        #expect(rig.source.performed.map(\.id) == ["notch"])
    }

    @Test func anItemWithoutAFrameIsNotRevealedEither() async {
        let rig = Rig()
        await rig.open()
        rig.bar.choose("flat")
        #expect(rig.sections.log.isEmpty)
        #expect(rig.source.performed.map(\.id) == ["flat"])
    }

    @Test func whenEverythingIsAlreadyShownThereIsNothingToReveal() async {
        let rig = Rig()
        rig.sections.level = .all
        await rig.open()
        rig.bar.choose("parked")
        #expect(rig.sections.log.isEmpty)
        #expect(rig.source.performed.map(\.id) == ["parked"])
    }

    @Test func anItemOfAShownSectionIsPressedWhereItIs() async {
        let rig = Rig()
        rig.layout = MenuBarLayout(screens: [Self.notched], hiddenSeparator: CGRect(x: 1_300, y: 1_093, width: 24, height: 24))
        rig.source.listed = [Self.item("section", x: 1_000)]
        rig.sections.level = .expanded
        await rig.open()
        #expect(rig.bar.entries.map(\.reason) == [.hiddenSection])
        rig.bar.choose("section")
        #expect(rig.sections.log.isEmpty)
        #expect(rig.source.performed.map(\.id) == ["section"])
    }

    @Test func aSecondItemChosenBeforeTheRestoreDoesNotRevealAgainOrLoseTheFirstLevel() async {
        let rig = Rig()
        rig.sections.level = .expanded
        rig.sections.onReveal = { rig.source.frames["parked"] = Self.onScreenAgain }
        rig.source.listed.append(Self.item("late", x: -9_100))
        await rig.open()
        rig.bar.choose("parked")
        rig.scheduler.advance(by: MenuBarItemsBar.revealPoll)
        await rig.open()
        rig.bar.choose("late")
        #expect(rig.sections.log == ["revealAll"])
        #expect(rig.source.performed.map(\.id) == ["parked", "late"])
        // The second press pushes the restore out, so it does not come under the second menu.
        rig.scheduler.advance(by: MenuBarItemsBar.restoreDelay - .milliseconds(1))
        #expect(rig.sections.log == ["revealAll"])
        rig.scheduler.advance(by: .milliseconds(1))
        #expect(rig.sections.log == ["revealAll", "restore:expanded"])
    }

    // MARK: when the bar is used

    @Test func theBarReplacesTheInPlaceExpandOnlyWithTheHiderOnTheSettingOnAndAccessibilityGranted() {
        #expect(MenuBarItemsBar.isAvailable(hiderOn: true, settingOn: true, accessibilityGranted: true))
        #expect(!MenuBarItemsBar.isAvailable(hiderOn: false, settingOn: true, accessibilityGranted: true))
        #expect(!MenuBarItemsBar.isAvailable(hiderOn: true, settingOn: false, accessibilityGranted: true))
        #expect(!MenuBarItemsBar.isAvailable(hiderOn: true, settingOn: true, accessibilityGranted: false))
    }
}
