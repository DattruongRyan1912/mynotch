import CoreGraphics
import Testing
@testable import MyNotchCore

@Suite struct MenuBarItemsReachabilityTests {
    /// A 14" display with a notch: 1 728 x 1 117 points, a 38-point bar, and the notch covering the middle 200 points.
    private let notched = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117), barHeight: 38, notchGap: 764...964)
    /// A display without one.
    private let plain = MenuBarScreen(frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117), barHeight: 24)

    /// A status item's window: 24 points tall, hung from the top edge (AppKit coordinates, y up).
    private func frame(x: CGFloat, width: CGFloat = 24, top: CGFloat = 1_117) -> CGRect {
        CGRect(x: x, y: top - 24, width: width, height: 24)
    }

    private func layout(
        _ screen: MenuBarScreen? = nil, hidden: CGRect? = nil, always: CGRect? = nil
    ) -> MenuBarLayout {
        MenuBarLayout(screens: [screen ?? notched], hiddenSeparator: hidden, alwaysHiddenSeparator: always)
    }

    private func item(
        _ id: String, _ frame: CGRect, order: Int = 0, title: String? = nil, details: String? = nil,
        owner: String = "App", bundleID: String? = "com.example.app"
    ) -> MenuBarItem {
        MenuBarItem(id: id, pid: 100, ownerBundleID: bundleID, ownerName: owner, title: title, details: details, frame: frame, order: order)
    }

    // MARK: the display's notch

    @Test func theNotchGapIsWhatTheTwoAuxiliaryAreasLeaveFree() {
        let gap = MenuBarScreen.notchGap(frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117), leftWidth: 764, rightWidth: 764)
        #expect(gap == 764...964)
        // A display that is not at the origin: the gap moves with it.
        let moved = MenuBarScreen.notchGap(frame: CGRect(x: 1_728, y: 0, width: 1_728, height: 1_117), leftWidth: 764, rightWidth: 764)
        #expect(moved == 2_492...2_692)
    }

    @Test func noNotchWhenEitherAreaIsMissingOrTheyLeaveNoGap() {
        let display = CGRect(x: 0, y: 0, width: 1_728, height: 1_117)
        #expect(MenuBarScreen.notchGap(frame: display, leftWidth: nil, rightWidth: 764) == nil)
        #expect(MenuBarScreen.notchGap(frame: display, leftWidth: 764, rightWidth: nil) == nil)
        #expect(MenuBarScreen.notchGap(frame: display, leftWidth: 864, rightWidth: 864) == nil)
        #expect(MenuBarScreen.notchGap(frame: display, leftWidth: 900, rightWidth: 900) == nil)
        #expect(MenuBarScreen.notchGap(frame: display, leftWidth: 0, rightWidth: 0) == nil)
    }

    // MARK: AX coordinates

    @Test func anAccessibilityFrameIsFlippedAgainstThePrimaryDisplaysHeight() {
        // The menu bar item at the top right of a 1 117-point-high main display: y is 0 in AX, 1 093 in AppKit.
        let ax = CGRect(x: 1_540, y: 0, width: 28, height: 24)
        #expect(MenuBarCoordinates.appKitFrame(fromAccessibility: ax, primaryHeight: 1_117) == CGRect(x: 1_540, y: 1_093, width: 28, height: 24))
    }

    @Test func aDisplayAboveTheMainOneIsAtNegativeAccessibilityYAndAboveItsHeightInAppKit() {
        // A display above the main one: its bar is at AX y = -1 080 (its top), AppKit y = 1 117 + 1 080 - 24.
        let ax = CGRect(x: 100, y: -1_080, width: 28, height: 24)
        #expect(MenuBarCoordinates.appKitFrame(fromAccessibility: ax, primaryHeight: 1_117) == CGRect(x: 100, y: 2_173, width: 28, height: 24))
    }

    @Test func aDisplayLeftOfTheMainOneKeepsItsNegativeX() {
        let ax = CGRect(x: -300, y: 0, width: 28, height: 24)
        #expect(MenuBarCoordinates.appKitFrame(fromAccessibility: ax, primaryHeight: 900) == CGRect(x: -300, y: 876, width: 28, height: 24))
    }

    @Test func theConversionRoundTrips() {
        for ax in [CGRect(x: 10, y: 0, width: 30, height: 24), CGRect(x: -9_000, y: -1_080, width: 30, height: 24), CGRect(x: 5, y: 700, width: 1, height: 1)] {
            let appKit = MenuBarCoordinates.appKitFrame(fromAccessibility: ax, primaryHeight: 1_117)
            #expect(MenuBarCoordinates.accessibilityFrame(fromAppKit: appKit, primaryHeight: 1_117) == ax)
        }
    }

    // MARK: the reachability rule

    @Test func anItemOnTheBarClearOfTheNotchIsReachableAndListedNowhere() {
        #expect(MenuBarReachability.reason(for: frame(x: 1_500), in: layout()) == nil)
        #expect(MenuBarReachability.reason(for: frame(x: 100), in: layout()) == nil)
    }

    @Test func aFrameWithoutAnAreaIsZeroSize() {
        #expect(MenuBarReachability.reason(for: CGRect(x: 1_500, y: 1_093, width: 0, height: 24), in: layout()) == .zeroSize)
        #expect(MenuBarReachability.reason(for: CGRect(x: 1_500, y: 1_093, width: 24, height: 0), in: layout()) == .zeroSize)
        #expect(MenuBarReachability.reason(for: .null, in: layout()) == .zeroSize)
        #expect(MenuBarReachability.reason(for: .zero, in: layout()) == .zeroSize)
    }

    @Test func anItemOffTheScreenOrBelowTheBarIsOffScreen() {
        #expect(MenuBarReachability.reason(for: frame(x: -9_000), in: layout()) == .offScreen)
        #expect(MenuBarReachability.reason(for: frame(x: 1_728), in: layout()) == .offScreen)
        #expect(MenuBarReachability.reason(for: CGRect(x: 1_500, y: 500, width: 24, height: 24), in: layout()) == .offScreen)
        #expect(MenuBarReachability.reason(for: frame(x: 1_500), in: MenuBarLayout(screens: [])) == .offScreen)
    }

    @Test func anItemOverTheNotchIsUnderTheNotch() {
        #expect(MenuBarReachability.reason(for: frame(x: 800), in: layout()) == .underNotch)
        // Straddling either edge: part of it is behind the notch.
        #expect(MenuBarReachability.reason(for: frame(x: 940, width: 40), in: layout()) == .underNotch)
        #expect(MenuBarReachability.reason(for: frame(x: 745, width: 40), in: layout()) == .underNotch)
    }

    @Test func anItemTouchingTheNotchsEdgeButNotBehindItIsReachable() {
        #expect(MenuBarReachability.reason(for: frame(x: 964), in: layout()) == nil)
        #expect(MenuBarReachability.reason(for: frame(x: 740), in: layout()) == nil)
    }

    @Test func aDisplayWithoutANotchHasNoGap() {
        #expect(MenuBarReachability.reason(for: frame(x: 800), in: layout(plain)) == nil)
    }

    @Test func theNotchGapOfAnotherDisplayDoesNotApply() {
        let external = MenuBarScreen(frame: CGRect(x: 1_728, y: -300, width: 2_560, height: 1_440), barHeight: 24)
        let two = MenuBarLayout(screens: [notched, external])
        // x 2 600 is the same x as nothing on the notch's display; on the external display it is simply an item.
        #expect(MenuBarReachability.reason(for: frame(x: 2_600, top: 1_140), in: two) == nil)
        #expect(MenuBarReachability.reason(for: frame(x: 800), in: two) == .underNotch)
    }

    // MARK: MyNotch's own sections

    @Test func anItemLeftOfTheHiddenSeparatorIsInTheHiddenSection() {
        let shown = layout(hidden: frame(x: 1_200))
        #expect(MenuBarReachability.reason(for: frame(x: 1_000), in: shown) == .hiddenSection)
        #expect(MenuBarReachability.reason(for: frame(x: 1_250), in: shown) == nil)
    }

    @Test func anItemLeftOfTheAlwaysHiddenSeparatorIsInTheAlwaysHiddenSection() {
        let all = layout(hidden: frame(x: 1_200), always: frame(x: 1_100))
        #expect(MenuBarReachability.reason(for: frame(x: 1_000), in: all) == .alwaysHiddenSection)
        #expect(MenuBarReachability.reason(for: frame(x: 1_150), in: all) == .hiddenSection)
        #expect(MenuBarReachability.reason(for: frame(x: 1_250), in: all) == nil)
    }

    @Test func withoutSeparatorFramesNoSectionIsKnown() {
        // Collapsed, a separator's window is 10 000 points wide and says nothing; the items it hides are off the screen.
        #expect(MenuBarReachability.reason(for: frame(x: 1_000), in: layout()) == nil)
        #expect(MenuBarReachability.reason(for: frame(x: -8_900), in: layout()) == .offScreen)
    }

    @Test func aSeparatorOnAnotherDisplayDoesNotMakeItemsHidden() {
        let external = MenuBarScreen(frame: CGRect(x: 1_728, y: -300, width: 2_560, height: 1_440), barHeight: 24)
        let two = MenuBarLayout(screens: [notched, external], hiddenSeparator: frame(x: 4_000, top: 1_140))
        #expect(MenuBarReachability.reason(for: frame(x: 1_000), in: two) == nil)
        #expect(MenuBarReachability.reason(for: frame(x: 3_000, top: 1_140), in: two) == .hiddenSection)
    }

    @Test func theNotchOutranksTheSectionsBecauseNoClickCanReachUnderIt() {
        #expect(MenuBarReachability.reason(for: frame(x: 800), in: layout(hidden: frame(x: 1_200))) == .underNotch)
    }

    // MARK: what the bar lists, and in which order

    @Test func theListHoldsOnlyTheItemsThatNeedTheBar() {
        let items = [item("a", frame(x: 1_500)), item("b", frame(x: -9_000)), item("c", frame(x: 100))]
        #expect(MenuBarReachability.entries(from: items, layout: layout()).map(\.id) == ["b"])
    }

    @Test func theListIsInMenuBarOrderLeftToRight() {
        let items = [
            item("d", frame(x: 1_000), order: 0),
            item("a", frame(x: -9_000), order: 1),
            item("c", frame(x: 800), order: 2),
            item("b", frame(x: -9_040), order: 3),
        ]
        let entries = MenuBarReachability.entries(from: items, layout: layout(hidden: frame(x: 1_200)))
        #expect(entries.map(\.id) == ["b", "a", "c", "d"])
        #expect(entries.map(\.reason) == [.offScreen, .offScreen, .underNotch, .hiddenSection])
    }

    @Test func itemsAtTheSamePlaceKeepTheOrderTheySourceGaveThem() {
        let parked = frame(x: -9_999)
        let items = [item("x", parked, order: 2), item("y", parked, order: 0), item("z", parked, order: 1)]
        #expect(MenuBarReachability.entries(from: items, layout: layout()).map(\.id) == ["y", "z", "x"])
    }

    @Test func itemsWithoutAFrameComeLastInTheSourceOrder() {
        let items = [
            item("none2", .zero, order: 5), item("far", frame(x: -9_000), order: 9), item("none1", .zero, order: 1),
            item("notch", frame(x: 800), order: 3),
        ]
        let entries = MenuBarReachability.entries(from: items, layout: layout())
        #expect(entries.map(\.id) == ["far", "notch", "none1", "none2"])
        #expect(entries.last?.reason == .zeroSize)
    }

    @Test func noItemsMeansNoEntries() {
        #expect(MenuBarReachability.entries(from: [], layout: layout()).isEmpty)
    }

    // MARK: clickable right now

    @Test func anItemIsClickableOnlyOnABarAndClearOfTheNotch() {
        #expect(MenuBarReachability.isClickable(frame(x: 1_500), in: [notched]))
        #expect(!MenuBarReachability.isClickable(frame(x: 800), in: [notched]))
        #expect(!MenuBarReachability.isClickable(frame(x: -9_000), in: [notched]))
        #expect(!MenuBarReachability.isClickable(.zero, in: [notched]))
        #expect(!MenuBarReachability.isClickable(frame(x: 1_500), in: []))
    }

    // MARK: whose items are listed

    @Test func theOwnProcessAndAppleSystemItemsAreLeftOut() {
        #expect(!MenuBarItemOwners.isListed(bundleID: "io.lucasvu.mynotch", pid: 42, ownPID: 42))
        #expect(!MenuBarItemOwners.isListed(bundleID: "com.apple.controlcenter", pid: 7, ownPID: 42))
        #expect(!MenuBarItemOwners.isListed(bundleID: "com.apple.systemuiserver", pid: 8, ownPID: 42))
    }

    @Test func otherAppsAreListedEvenWithoutABundleIDOrWithALookAlikePrefix() {
        #expect(MenuBarItemOwners.isListed(bundleID: "com.dropbox.client", pid: 7, ownPID: 42))
        #expect(MenuBarItemOwners.isListed(bundleID: nil, pid: 7, ownPID: 42))
        #expect(MenuBarItemOwners.isListed(bundleID: "com.applesauce.app", pid: 7, ownPID: 42))
    }

    // MARK: tooltip

    @Test func theTooltipIsTheAppNameWhenTheItemHasNoTitle() {
        #expect(item("a", .zero, owner: "Dropbox").toolTip == "Dropbox")
        #expect(item("a", .zero, title: "  ", details: "", owner: "Dropbox").toolTip == "Dropbox")
    }

    @Test func theTooltipAddsTheItemsTitleOrDescriptionToTheAppName() {
        #expect(item("a", .zero, title: "Sync paused", owner: "Dropbox").toolTip == "Dropbox: Sync paused")
        #expect(item("a", .zero, title: nil, details: "Trạng thái", owner: "Dropbox").toolTip == "Dropbox: Trạng thái")
        #expect(item("a", .zero, title: "Một", details: "Hai", owner: "Dropbox").toolTip == "Dropbox: Một")
    }

    @Test func aTitleThatIsTheAppNameIsNotRepeated() {
        #expect(item("a", .zero, title: "Dropbox", owner: "Dropbox").toolTip == "Dropbox")
    }
}
