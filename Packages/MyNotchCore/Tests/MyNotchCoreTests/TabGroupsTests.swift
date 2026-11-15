import Observation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// The thirteen pages of the notch, as their modules name them.
private let allPages: [ModuleID] = [
    "clipboard", "media", "translation", "aiagents", "calendar", "todo", "screenshot", "shelf", "timer", "performance", "battery", "ports",
    "shortcuts", "windows", "system",
]

@Suite struct TabGroupsTests {
    let defaults: Set<ModuleID> = ["clipboard", "media", "translation", "aiagents", "calendar", "todo"]

    // MARK: the defaults

    @Test func theDefaultBarIsTheSixPagesUsedMost() {
        #expect(TabGroups.defaultBar == ["clipboard", "media", "translation", "aiagents", "calendar", "todo"])
    }

    @Test func untilTheSettingIsSetEverythingButTheDefaultBarIsInKhac() {
        let overflow = TabGroups.overflow(stored: nil, order: [], available: allPages)
        #expect(overflow == Set(allPages).subtracting(defaults))
        #expect(overflow.count == 9)
        for page in ["screenshot", "shelf", "timer", "performance", "battery", "ports", "shortcuts", "windows", "system"] as [ModuleID] {
            #expect(overflow.contains(page), "\(page)")
        }
    }

    @Test func aPageOfAModuleTheDefaultsDoNotKnowIsInKhacByDefault() {
        let overflow = TabGroups.overflow(stored: nil, order: [], available: ["clipboard", "somethingnew"])
        #expect(overflow == ["somethingnew"])
    }

    @Test func anOrderStoredBeforeDoesNotKeepEveryPageOnTheBar() {
        // A user who arranged the order long ago has never set the placement: they get the defaults, whatever the order says.
        let overflow = TabGroups.overflow(stored: nil, order: allPages.reversed(), available: allPages)
        #expect(overflow == Set(allPages).subtracting(defaults))
    }

    // MARK: once it is set, the defaults are not applied again

    @Test func onceSetTheStoredListIsWhatIsInKhacAndTheDefaultsAreNotAppliedAgain() {
        // The user moved everything onto the bar: Khác is empty, which is not "never set".
        #expect(TabGroups.overflow(stored: [], order: allPages, available: allPages).isEmpty)
        // Or put two pages in it.
        #expect(TabGroups.overflow(stored: ["clipboard", "todo"], order: allPages, available: allPages) == ["clipboard", "todo"])
    }

    @Test func aPageThatIsInTheStoredListButDoesNotRunIsNotReported() {
        #expect(TabGroups.overflow(stored: ["gone", "timer"], order: allPages, available: ["timer", "media"]) == ["timer"])
    }

    // MARK: a new page

    @Test func aModuleAddedAfterTheSettingWasSetGoesToKhac() {
        let overflow = TabGroups.overflow(stored: [], order: ["clipboard", "media"], available: ["clipboard", "media", "newone"])
        #expect(overflow == ["newone"])
    }

    @Test func aPageAlreadyInTheOrderIsNotNewAndStaysWhereTheArrangementPutIt() {
        let overflow = TabGroups.overflow(stored: ["timer"], order: ["timer", "ports", "media"], available: ["timer", "ports", "media"])
        #expect(overflow == ["timer"], "ports is in the order, so it was placed: on the bar")
    }

    @Test func aDefaultBarPageNobodyHasPlacedYetIsOnTheBarAfterTheSettingWasSet() {
        // Calendar was off when the user arranged the pages; switched on later it has its default.
        let overflow = TabGroups.overflow(stored: ["timer"], order: ["media", "timer"], available: ["media", "timer", "calendar", "brandnew"])
        #expect(overflow == ["timer", "brandnew"])
    }

    // MARK: merged order with Khác

    @Test func theBarAndKhacEachKeepTheUsersOrder() {
        let ordered = TabOrder.merged(stored: ["timer", "media", "ports", "clipboard"], available: ["clipboard", "media", "ports", "timer"])
        let split = TabGroups.split(ordered: ordered, overflow: ["timer", "ports"])
        #expect(split.bar == ["media", "clipboard"])
        #expect(split.overflow == ["timer", "ports"])
        #expect(split.bar + split.overflow != ordered, "the groups are filters of one order, not a reordering of it")
        #expect(Set(split.bar + split.overflow) == Set(ordered))
    }

    @Test func nothingInKhacIsAllBarAndNothingOnTheBarIsAllKhac() {
        #expect(TabGroups.split(ordered: ["a", "b"], overflow: []) == .init(bar: ["a", "b"], overflow: []))
        #expect(TabGroups.split(ordered: ["a", "b"], overflow: ["a", "b"]) == .init(bar: [], overflow: ["a", "b"]))
    }

    // MARK: the Settings page moves a page

    let start = TabGroups.Arrangement(bar: ["a", "b", "c"], overflow: ["x", "y"])

    @Test func aPageMovesWithinItsSection() {
        #expect(TabGroups.moving("c", to: .bar, at: 0, in: start) == .init(bar: ["c", "a", "b"], overflow: ["x", "y"]))
        #expect(TabGroups.moving("a", to: .bar, at: 2, in: start) == .init(bar: ["b", "c", "a"], overflow: ["x", "y"]))
        #expect(TabGroups.moving("y", to: .overflow, at: 0, in: start) == .init(bar: ["a", "b", "c"], overflow: ["y", "x"]))
    }

    @Test func aPageMovesBetweenTheSections() {
        #expect(TabGroups.moving("b", to: .overflow, at: 1, in: start) == .init(bar: ["a", "c"], overflow: ["x", "b", "y"]))
        #expect(TabGroups.moving("x", to: .bar, at: 3, in: start) == .init(bar: ["a", "b", "c", "x"], overflow: ["y"]))
        #expect(TabGroups.moving("x", to: .bar, at: 0, in: start) == .init(bar: ["x", "a", "b", "c"], overflow: ["y"]))
    }

    @Test func aPageDroppedOnARowGoesJustBeforeThatRowWhicheverWayItCame() {
        // Downward in the same section: the page lands before the row it was dropped on, not after it.
        #expect(TabGroups.moving("a", before: "c", in: start) == .init(bar: ["b", "a", "c"], overflow: ["x", "y"]))
        #expect(TabGroups.moving("a", before: "b", in: start) == .init(bar: ["a", "b", "c"], overflow: ["x", "y"]), "just above where it is: no move")
        // Upward.
        #expect(TabGroups.moving("c", before: "a", in: start) == .init(bar: ["c", "a", "b"], overflow: ["x", "y"]))
        #expect(TabGroups.moving("y", before: "x", in: start) == .init(bar: ["a", "b", "c"], overflow: ["y", "x"]))
        #expect(TabGroups.moving("x", before: "y", in: start) == .init(bar: ["a", "b", "c"], overflow: ["x", "y"]))
        // From the other section.
        #expect(TabGroups.moving("x", before: "b", in: start) == .init(bar: ["a", "x", "b", "c"], overflow: ["y"]))
        #expect(TabGroups.moving("b", before: "y", in: start) == .init(bar: ["a", "c"], overflow: ["x", "b", "y"]))
    }

    @Test func aDropOnItselfOrOnSomethingThatIsNotThereChangesNothing() {
        #expect(TabGroups.moving("b", before: "b", in: start) == start)
        #expect(TabGroups.moving("zzz", before: "a", in: start) == start)
        #expect(TabGroups.moving("a", before: "zzz", in: start) == start)
    }

    @Test func theIndexIsHeldToTheSectionAndAnUnknownPageChangesNothing() {
        #expect(TabGroups.moving("a", to: .overflow, at: 99, in: start) == .init(bar: ["b", "c"], overflow: ["x", "y", "a"]))
        #expect(TabGroups.moving("a", to: .overflow, at: -4, in: start) == .init(bar: ["b", "c"], overflow: ["a", "x", "y"]))
        #expect(TabGroups.moving("zzz", to: .bar, at: 0, in: start) == start)
    }

    @Test func movingTheLastPageOutOfASectionLeavesItEmpty() {
        let one = TabGroups.Arrangement(bar: ["a"], overflow: [])
        #expect(TabGroups.moving("a", to: .overflow, at: 0, in: one) == .init(bar: [], overflow: ["a"]))
    }

    // MARK: what is stored

    @Test func whatIsOnScreenIsStoredAsTheOrderAndTheOverflow() {
        let visible = TabGroups.Arrangement(bar: ["b", "a"], overflow: ["x"])
        let stored = TabGroups.stored(for: visible, order: [], overflow: nil)
        #expect(stored.order == ["b", "a", "x"])
        #expect(stored.overflow == ["x"])
    }

    @Test func aModuleThatIsOffKeepsItsOldPlace() {
        // `off` was in Khác and is not on screen: it stays in Khác, and its place in the order stays after the pages on screen.
        let visible = TabGroups.Arrangement(bar: ["a"], overflow: ["x"])
        let stored = TabGroups.stored(for: visible, order: ["a", "off", "x"], overflow: ["x", "off"])
        #expect(stored.order == ["a", "x", "off"])
        #expect(stored.overflow == ["x", "off"])
    }

    @Test func theFirstSaveKeepsTheDefaultOfAModuleThatIsOff() {
        // Never set: `shortcuts` is off and not a default-bar page, so it goes into Khác; `calendar` is off and is a default-bar page, so it
        // is not put in it.
        let visible = TabGroups.Arrangement(bar: ["clipboard"], overflow: ["timer"])
        let stored = TabGroups.stored(for: visible, order: ["clipboard", "shortcuts", "calendar", "timer"], overflow: nil)
        #expect(stored.overflow.contains("shortcuts"))
        #expect(!stored.overflow.contains("calendar"))
        #expect(stored.overflow.first == "timer")
    }

    @Test func whatIsStoredReadsBackAsWhatWasOnScreen() {
        let visible = TabGroups.Arrangement(bar: ["media", "clipboard"], overflow: ["timer", "ports"])
        let stored = TabGroups.stored(for: visible, order: [], overflow: nil)
        let available: [ModuleID] = ["clipboard", "media", "ports", "timer", "newone"]
        let ordered = TabOrder.merged(stored: stored.order, available: available)
        let overflow = TabGroups.overflow(stored: stored.overflow, order: stored.order, available: available)
        let read = TabGroups.split(ordered: ordered, overflow: overflow)
        #expect(read.bar == ["media", "clipboard"])
        #expect(read.overflow == ["timer", "ports", "newone"], "and the module nobody had seen goes last, into Khác")
    }
}

@Suite struct RegistryTabGroupsTests {
    func make() async -> RegistryHarness {
        let harness = Harness([FakeModule("a", order: 1), FakeModule("b", order: 2), FakeModule("c", order: 3)])
        await harness.registry.bootstrap()
        return harness
    }

    @Test func untilSetEveryPageOfAModuleTheDefaultsDoNotKnowIsInKhac() async {
        let harness = await make()
        #expect(harness.registry.barTabs.isEmpty)
        #expect(harness.registry.overflowTabs.map(\.id) == ["a", "b", "c"])
        #expect(harness.registry.tabs.map(\.id) == ["a", "b", "c"], "tabs is still every page, in the user's order")
        #expect(harness.registry.isOverflow("b"))
    }

    @Test func theDefaultsPutTheirPagesOnTheBar() async {
        let harness = Harness([FakeModule("clipboard", order: 1), FakeModule("timer", order: 2), FakeModule("media", order: 3)])
        await harness.registry.bootstrap()
        #expect(harness.registry.barTabs.map(\.id) == ["clipboard", "media"])
        #expect(harness.registry.overflowTabs.map(\.id) == ["timer"])
    }

    @Test func settingThePlacementMovesPagesAndKeepsEachSectionInTheUsersOrder() async {
        let harness = await make()
        harness.settings.set(["c", "a", "b"], for: ModuleRegistry.tabOrderKey)
        harness.settings.set([ModuleID]?.some(["a"]), for: ModuleRegistry.tabOverflowKey)
        #expect(harness.registry.barTabs.map(\.id) == ["c", "b"])
        #expect(harness.registry.overflowTabs.map(\.id) == ["a"])
        #expect(!harness.registry.isOverflow("c"))
    }

    @Test func aModuleNobodyPlacedGoesToKhacAndOnePlacedKeepsItsPlace() async {
        let harness = await make()
        harness.settings.set(["a", "b"], for: ModuleRegistry.tabOrderKey)
        harness.settings.set([ModuleID]?.some([]), for: ModuleRegistry.tabOverflowKey)
        // c is in neither: it is new.
        #expect(harness.registry.barTabs.map(\.id) == ["a", "b"])
        #expect(harness.registry.overflowTabs.map(\.id) == ["c"])
    }

    @Test func emptyingKhacIsNotTheSameAsNeverHavingSetIt() async {
        let harness = await make()
        harness.putEveryTabOnTheBar()
        #expect(harness.registry.overflowTabs.isEmpty)
        #expect(harness.registry.barTabs.map(\.id) == ["a", "b", "c"])
        // Reset is what goes back to the defaults.
        harness.settings.reset(ModuleRegistry.tabOverflowKey)
        #expect(harness.registry.overflowTabs.map(\.id) == ["a", "b", "c"])
    }

    @Test func aStoppedModuleKeepsItsPlacementForWhenItComesBack() async {
        let harness = await make()
        harness.settings.set(["a", "b", "c"], for: ModuleRegistry.tabOrderKey)
        harness.settings.set([ModuleID]?.some(["b"]), for: ModuleRegistry.tabOverflowKey)
        await harness.registry.setEnabled(false, for: "b")
        #expect(harness.registry.overflowTabs.isEmpty)
        #expect(harness.registry.barTabs.map(\.id) == ["a", "c"])
        await harness.registry.setEnabled(true, for: "b")
        #expect(harness.registry.overflowTabs.map(\.id) == ["b"])
    }

    @Test func aChangeOfThePlacementNotifiesWhoReadsTheBarOrKhac() async {
        let harness = await make()
        nonisolated(unsafe) var bar = 0, khac = 0
        withObservationTracking { _ = harness.registry.barTabs } onChange: { bar += 1 }
        withObservationTracking { _ = harness.registry.overflowTabs } onChange: { khac += 1 }
        harness.settings.set([ModuleID]?.some([]), for: ModuleRegistry.tabOverflowKey)
        #expect(bar == 1 && khac == 1)
    }

    @Test func thePlacementIsKeptAsAListOfIdsUnderTheKeyTheBriefNames() async {
        #expect(ModuleRegistry.tabOverflowKey.name == "app.tabOverflow")
        let harness = await make()
        harness.settings.set([ModuleID]?.some(["b", "c"]), for: ModuleRegistry.tabOverflowKey)
        #expect(harness.settings.value(ModuleRegistry.tabOverflowKey) == ["b", "c"])
        // The same list read as a plain array of ids, as it is on disk.
        let plain = SettingKey<[ModuleID]>("app.tabOverflow", default: [])
        #expect(harness.settings.value(plain) == ["b", "c"])
    }

    /// What the Settings page does when a page is moved: the arrangement as the registry shows it, moved, stored, and read back.
    func arrange(_ harness: RegistryHarness, _ change: (TabGroups.Arrangement) -> TabGroups.Arrangement) {
        let shown = TabGroups.Arrangement(bar: harness.registry.barTabs.map(\.id), overflow: harness.registry.overflowTabs.map(\.id))
        let stored = TabGroups.stored(
            for: change(shown), order: harness.settings.value(ModuleRegistry.tabOrderKey), overflow: harness.settings.value(ModuleRegistry.tabOverflowKey)
        )
        harness.settings.set(stored.order, for: ModuleRegistry.tabOrderKey)
        harness.settings.set(stored.overflow, for: ModuleRegistry.tabOverflowKey)
    }

    @Test func movingAPageInTheSettingsPageMovesItBetweenTheSections() async {
        let harness = Harness([FakeModule("clipboard", order: 1), FakeModule("media", order: 2), FakeModule("timer", order: 3), FakeModule("ports", order: 4)])
        await harness.registry.bootstrap()
        #expect(harness.registry.barTabs.map(\.id) == ["clipboard", "media"])
        #expect(harness.registry.overflowTabs.map(\.id) == ["timer", "ports"])
        // "Chuyển vào Khác": media goes to the end of Khác.
        arrange(harness) { TabGroups.moving("media", to: .overflow, at: .max, in: $0) }
        #expect(harness.registry.barTabs.map(\.id) == ["clipboard"])
        #expect(harness.registry.overflowTabs.map(\.id) == ["timer", "ports", "media"])
        // "Đưa lên thanh": ports goes to the front of the bar.
        arrange(harness) { TabGroups.moving("ports", to: .bar, at: 0, in: $0) }
        #expect(harness.registry.barTabs.map(\.id) == ["ports", "clipboard"])
        #expect(harness.registry.overflowTabs.map(\.id) == ["timer", "media"])
        // Reordering inside Khác.
        arrange(harness) { TabGroups.moving("media", to: .overflow, at: 0, in: $0) }
        #expect(harness.registry.overflowTabs.map(\.id) == ["media", "timer"])
    }

    @Test func onceTheUserHasArrangedThemTheDefaultsAreNotAppliedAgain() async {
        let harness = Harness([FakeModule("clipboard", order: 1), FakeModule("timer", order: 2)])
        await harness.registry.bootstrap()
        // Everything onto the bar, which empties Khác.
        arrange(harness) { TabGroups.moving("timer", to: .bar, at: .max, in: $0) }
        #expect(harness.registry.overflowTabs.isEmpty)
        #expect(harness.settings.value(ModuleRegistry.tabOverflowKey) == [], "stored, as an empty list: not the same as never set")
        // A launch later: nothing re-applies the defaults.
        let again = Harness([FakeModule("clipboard", order: 1), FakeModule("timer", order: 2)])
        again.settings.set(harness.settings.value(ModuleRegistry.tabOrderKey), for: ModuleRegistry.tabOrderKey)
        again.settings.set(harness.settings.value(ModuleRegistry.tabOverflowKey), for: ModuleRegistry.tabOverflowKey)
        await again.registry.bootstrap()
        #expect(again.registry.overflowTabs.isEmpty)
        #expect(again.registry.barTabs.map(\.id) == ["clipboard", "timer"])
    }

    @Test func aModuleSwitchedOffKeepsItsPlaceInKhacWhenTheArrangementIsSaved() async {
        let harness = Harness([FakeModule("clipboard", order: 1), FakeModule("timer", order: 2), FakeModule("ports", order: 3)])
        await harness.registry.bootstrap()
        await harness.registry.setEnabled(false, for: "ports")
        arrange(harness) { TabGroups.moving("clipboard", to: .overflow, at: .max, in: $0) }
        await harness.registry.setEnabled(true, for: "ports")
        #expect(harness.registry.overflowTabs.map(\.id).contains("ports"), "it was in Khác and is again")
        #expect(harness.registry.barTabs.isEmpty)
    }
}
