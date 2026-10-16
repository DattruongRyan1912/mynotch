import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

private final class PageModule: FeatureModule {
    let descriptor: ModuleDescriptor
    init(_ id: ModuleID, order: Int) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: true, order: order)
    }
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: descriptor.displayName, systemImage: "circle", content: AnyView(EmptyView()))
    }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

/// The thirteen pages the notch has, in module order, by the ids their modules have.
private let thirteen: [ModuleID] = [
    "clipboard", "media", "translation", "aiagents", "calendar", "todo", "screenshot", "shelf", "timer", "performance", "battery", "ports",
    "windows",
]

private func harness(_ ids: [ModuleID] = thirteen) async -> RegistryHarness {
    let harness = RegistryHarness(ids.enumerated().map { PageModule($0.element, order: $0.offset) })
    await harness.registry.bootstrap()
    return harness
}

// MARK: the pages as the bar shows them

@Suite struct NotchPagesTests {
    let pages = NotchPages(bar: ["a", "b", "c"], overflow: ["x", "y"])

    @Test func theBarHoldsItsPagesThenOneKhacItem() {
        #expect(pages.items == ["a", "b", "c", NotchPages.moreID])
        #expect(pages.hasMore)
        #expect(pages.count == 5)
    }

    @Test func everythingCanBeOpenedAndTheFirstIsTheFirstPageOfTheBar() {
        #expect(pages.selectable == ["a", "b", "c", NotchPages.moreID, "x", "y"])
        #expect(pages.selectable.first == "a")
    }

    @Test func khacIsNotThereWhenItHoldsNothing() {
        let none = NotchPages(bar: ["a", "b"], overflow: [])
        #expect(!none.hasMore)
        #expect(none.items == ["a", "b"])
        #expect(none.selectable == ["a", "b"])
        #expect(none.item(of: NotchPages.moreID) == NotchPages.moreID, "nothing to show, but nothing to map to either")
    }

    @Test func aPageInKhacIsShownByTheKhacItemAndAPageOnTheBarByItself() {
        #expect(pages.item(of: "b") == "b")
        #expect(pages.item(of: "x") == NotchPages.moreID)
        #expect(pages.item(of: NotchPages.moreID) == NotchPages.moreID)
    }

    @Test func theSelectedStateAndTheBadge() {
        #expect(pages.selection(of: "b") == (item: "b", badge: nil))
        // A page in Khác: the Khác item is selected, badged with that page.
        #expect(pages.selection(of: "y") == (item: NotchPages.moreID, badge: "y"))
        // The grid is what the Khác item is: selected, with nothing to badge it with.
        #expect(pages.selection(of: NotchPages.moreID) == (item: NotchPages.moreID, badge: nil))
        #expect(pages.selection(of: nil) == (item: nil, badge: nil))
    }

    @Test func theIdOfKhacIsNeverAModulesAndIsAValidId() {
        #expect(ModuleID(rawValue: NotchPages.moreID.rawValue) == NotchPages.moreID)
        #expect(!thirteen.contains(NotchPages.moreID))
    }
}

// MARK: from the registry

@Suite struct NotchPagesRegistryTests {
    @Test func theThirteenPagesAreSixOnTheBarAndSevenInKhacByDefault() async {
        let harness = await harness()
        let pages = harness.registry.pages
        #expect(pages.bar == ["clipboard", "media", "translation", "aiagents", "calendar", "todo"])
        #expect(pages.overflow == ["screenshot", "shelf", "timer", "performance", "battery", "ports", "windows"])
        #expect(pages.items.count == 7, "six pages and Khác: the bar is about half as long")
        #expect(pages.items.last == NotchPages.moreID)
    }

    @Test func aNewModuleGoesToKhac() async {
        let harness = await harness(["clipboard", "media", "brandnew"])
        #expect(harness.registry.pages.bar == ["clipboard", "media"])
        #expect(harness.registry.pages.overflow == ["brandnew"])
    }

    @Test func aSinglePageIsOnTheBarWithNoKhacItem() async {
        let harness = await harness(["timer"])
        let pages = harness.registry.pages
        #expect(pages.bar == ["timer"] && pages.overflow.isEmpty && !pages.hasMore)
    }

    @Test func allInKhacLeavesAnItemWithJustKhacWhenThereAreSeveralPages() async {
        let harness = await harness(["timer", "ports"])
        let pages = harness.registry.pages
        #expect(pages.bar.isEmpty && pages.overflow == ["timer", "ports"])
        #expect(pages.items == [NotchPages.moreID])
        #expect(pages.selectable.first == NotchPages.moreID, "an open with no page in mind shows the grid")
    }

    @Test func khacIsHiddenWhenEveryPageIsOnTheBar() async {
        let harness = await harness()
        harness.putEveryTabOnTheBar()
        let pages = harness.registry.pages
        #expect(pages.overflow.isEmpty && !pages.hasMore)
        #expect(pages.items == thirteen)
        #expect(!pages.selectable.contains(NotchPages.moreID))
    }

    @Test func theGridIsAsTallAsItsPagesNeed() async {
        // 7 pages, two rows: 44 for the padding and the tab bar's band, and 2 x 54 and a gap.
        let harness = await harness()
        #expect(harness.registry.contentHeight(for: .open(NotchPages.moreID), tabUnderToast: nil) == CGFloat(44 + 2 * 54 + 8))
        #expect(harness.registry.contentHeight(for: .toast, tabUnderToast: NotchPages.moreID) == 160, "a toast keeps the grid's height")
        // A page keeps what it asks for.
        #expect(harness.registry.contentHeight(for: .open("timer"), tabUnderToast: nil) == NotchTab.defaultHeight)
    }

    @Test func theGridsHeightFollowsTheNumberOfRowsAndIsHeldToWhatATabGets() {
        for (count, expected) in [(1, 120.0), (4, 120), (5, 160), (8, 160), (9, 222), (12, 222), (13, 240), (40, 240)] {
            #expect(MoreTabGrid.contentHeight(pageCount: count) == CGFloat(expected), "\(count) pages")
        }
        #expect(MoreTabGrid.rows(for: 0) == 0 && MoreTabGrid.rows(for: 4) == 1 && MoreTabGrid.rows(for: 5) == 2)
        #expect(MoreTabGrid.columns == 4)
    }
}

// MARK: opening a page that is in Khác

@Suite struct NotchMoreModelTests {
    func model(_ harness: RegistryHarness) -> NotchViewModel {
        NotchViewModel(
            scheduler: harness.scheduler, availableTabs: { [registry = harness.registry] in registry.pages.selectable }, delays: { (.zero, .zero) }
        )
    }

    @Test func aPageInKhacOpensAsItselfAndTheBarMarksKhac() async {
        let harness = await harness()
        let model = model(harness)
        model.open(tab: "timer")
        #expect(model.state == .open("timer"), "the page itself is shown, not a grid")
        let pages = harness.registry.pages
        #expect(pages.selection(of: "timer") == (item: NotchPages.moreID, badge: "timer"))
        #expect(model.lastTab == "timer")
    }

    @Test func aModulesOwnOpenReachesAPageInKhacOrOnTheBar() async {
        let harness = await harness()
        let model = model(harness)
        // What `presenter.open(tab:)` does through the coordinator.
        #expect(model.openTab(of: "ports"))
        #expect(model.state == .open("ports"))
        #expect(model.openTab(of: "media"))
        #expect(model.state == .open("media"))
        #expect(!model.openTab(of: "notamodule"))
    }

    @Test func khacItselfOpensItsGridAndIsRememberedLikeAPage() async {
        let harness = await harness()
        let model = model(harness)
        model.open(tab: NotchPages.moreID)
        #expect(model.state == .open(NotchPages.moreID))
        model.close()
        model.open(tab: nil)
        #expect(model.state == .open(NotchPages.moreID), "the notch opens where it was left")
    }

    @Test func anOpenWithNoPageInMindShowsTheFirstPageOfTheBar() async {
        let harness = await harness()
        let model = model(harness)
        model.open(tab: nil)
        #expect(model.state == .open("clipboard"))
    }

    @Test func theLastPageInKhacIsWhereAHoverOpensAgain() async {
        let harness = await harness()
        let model = model(harness)
        model.open(tab: "battery")
        model.close()
        model.open(tab: nil, onPurpose: false)
        #expect(model.state == .open("battery"))
    }

    @Test func withKhacEmptyItsIdIsNotOpenableAndAnOpenFallsBack() async {
        let harness = await harness()
        harness.putEveryTabOnTheBar()
        let model = model(harness)
        model.open(tab: NotchPages.moreID)
        #expect(model.state == .open("clipboard"), "no Khác to open: the first page")
    }

    @Test func aDropOnAPageInKhacOpensItToo() async {
        let harness = await harness()
        let model = model(harness)
        model.dragEntered(tab: "screenshot")
        #expect(model.state == .open("screenshot"))
    }
}

// MARK: swipe

@Suite struct NotchMoreSwipeTests {
    let pages = NotchPages(bar: ["a", "b", "c"], overflow: ["x", "y"])

    func target(_ step: TabSwipeRecognizer.Step, from page: ModuleID) -> ModuleID? {
        step.target(state: .open(page), tabs: pages.items, enabled: true, systemAllows: true, stop: pages.item(of:))
    }

    @Test func theBarsPagesAreStopsInOrderAndKhacIsOneStopAtTheEnd() {
        #expect(target(.next, from: "a") == "b")
        #expect(target(.next, from: "b") == "c")
        #expect(target(.next, from: "c") == NotchPages.moreID, "past the last page of the bar is Khác, its grid")
        #expect(target(.next, from: NotchPages.moreID) == nil, "and Khác is the last stop")
        #expect(target(.previous, from: NotchPages.moreID) == "c")
        #expect(target(.previous, from: "a") == nil)
    }

    @Test func fromAPageInKhacTheStopIsKhacSoPreviousGoesToTheLastPageOfTheBar() {
        #expect(target(.previous, from: "x") == "c")
        #expect(target(.previous, from: "y") == "c", "every page in Khác is the one stop")
        #expect(target(.next, from: "x") == nil)
        #expect(target(.next, from: "y") == nil)
    }

    @Test func withNothingInKhacThereIsNoSuchStop() {
        let none = NotchPages(bar: ["a", "b"], overflow: [])
        #expect(TabSwipeRecognizer.Step.next.target(state: .open("b"), tabs: none.items, enabled: true, systemAllows: true, stop: none.item(of:)) == nil)
    }

    @Test func swipingStillObeysItsSwitchesAndAnUnknownPage() {
        #expect(TabSwipeRecognizer.Step.next.target(state: .open("a"), tabs: pages.items, enabled: false, systemAllows: true, stop: pages.item(of:)) == nil)
        #expect(TabSwipeRecognizer.Step.next.target(state: .open("a"), tabs: pages.items, enabled: true, systemAllows: false, stop: pages.item(of:)) == nil)
        #expect(target(.next, from: "zzz") == nil)
        #expect(TabSwipeRecognizer.Step.next.target(state: .closed, tabs: pages.items, enabled: true, systemAllows: true, stop: pages.item(of:)) == nil)
    }

    // The window controller, with the defaults: the bar is clipboard, media, then Khác (timer is in it).
    func controller() async -> (NotchWindowController, RegistryHarness) {
        let harness = await harness(["clipboard", "media", "timer", "ports"])
        let controller = NotchWindowController(
            displayID: 1, screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities, delays: { (.milliseconds(150), .milliseconds(300)) },
            captureHiding: { .never }, swipesBetweenTabs: { true }, systemAllowsSwipe: { true }
        )
        return (controller, harness)
    }

    func swipe(_ controller: NotchWindowController, _ distance: CGFloat) {
        controller.handleScroll(phase: .began, momentumPhase: [], deltaX: 0, deltaY: 0)
        for _ in 0..<5 { controller.handleScroll(phase: .changed, momentumPhase: [], deltaX: distance / 5, deltaY: 0) }
        controller.handleScroll(phase: .ended, momentumPhase: [], deltaX: 0, deltaY: 0)
    }

    @Test func aSwipeGoesThroughTheBarThenKhacAndBackAsTheControllerDoesIt() async {
        let (controller, _) = await controller()
        defer { controller.close() }
        controller.model.open(tab: "clipboard")
        swipe(controller, -200)
        #expect(controller.model.state == .open("media"))
        swipe(controller, -200)
        #expect(controller.model.state == .open(NotchPages.moreID), "Khác is the stop after the bar's last page")
        swipe(controller, -200)
        #expect(controller.model.state == .open(NotchPages.moreID), "and the last")
        swipe(controller, 200)
        #expect(controller.model.state == .open("media"))
    }

    @Test func fromAPageInKhacASwipeBackGoesToTheLastPageOfTheBar() async {
        let (controller, _) = await controller()
        defer { controller.close() }
        controller.model.open(tab: "ports")
        swipe(controller, 200)
        #expect(controller.model.state == .open("media"))
        controller.model.open(tab: "timer")
        swipe(controller, -200)
        #expect(controller.model.state == .open("timer"), "there is no stop after Khác")
    }
}

// MARK: the bar drawn

@Suite struct NotchMoreBarTests {
    func tabs(_ ids: [ModuleID]) -> [NotchTab] {
        ids.map { NotchTab(id: $0, title: $0.rawValue, systemImage: "circle.fill", content: AnyView(EmptyView())) }
    }

    func render(_ selected: ModuleID?, badge: String? = nil) throws -> NSBitmapImageRep {
        let items = tabs(["a", "b", NotchPages.moreID])
        let bar = TabBar(tabs: items, selected: selected, badges: badge.map { [NotchPages.moreID: $0] } ?? [:]) { _ in }
            .environment(\.notchAccent, .red)
            .padding(20)
            .background(Color.black)
        let renderer = ImageRenderer(content: bar)
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in rect: CGRect) -> Int {
        var count = 0
        for y in Int(rect.minY * 2)..<Int(rect.maxY * 2) {
            for x in Int(rect.minX * 2)..<Int(rect.maxX * 2) {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), let q = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(p.redComponent - q.redComponent) > 0.1 || abs(p.greenComponent - q.greenComponent) > 0.1 { count += 1 }
            }
        }
        return count
    }

    /// The Khác item's cell, in points of the render (20 of padding, two items and their spacing before it).
    var khacCell: CGRect {
        CGRect(x: 20 + 2 * (TabBarMetrics.iconSize.width + TabBarMetrics.spacing), y: 20, width: TabBarMetrics.iconSize.width, height: TabBarMetrics.iconSize.height)
    }

    @Test func khacShowsAsSelectedWhileOneOfItsPagesIsOpen() throws {
        let none = try render(nil)
        let selected = try render(NotchPages.moreID)
        #expect(difference(none, selected, in: khacCell) > 50, "the accent behind the Khác item")
        // And nothing else on the bar moved.
        #expect(difference(none, selected, in: CGRect(x: 0, y: 0, width: 20 + 2 * (TabBarMetrics.iconSize.width + TabBarMetrics.spacing) - 1, height: 64)) == 0)
    }

    @Test func theBadgeIsASmallIconOnTheKhacItemOnlyWhileItIsSelected() throws {
        let selected = try render(NotchPages.moreID)
        let badged = try render(NotchPages.moreID, badge: "timer")
        #expect(difference(selected, badged, in: khacCell.insetBy(dx: -4, dy: -4)) > 10, "the page's icon is in the corner of the item")
        // The corner it is in is the bottom right; the top left of the item is as it was.
        let topLeft = CGRect(x: khacCell.minX, y: khacCell.minY, width: 8, height: 6)
        #expect(difference(selected, badged, in: topLeft) == 0)
        // A badge for an item that is not selected is not drawn.
        let unselected = try render(nil)
        let unselectedBadged = try render(nil, badge: "timer")
        #expect(difference(unselected, unselectedBadged, in: khacCell.insetBy(dx: -4, dy: -4)) == 0)
    }

    @Test func theBarHasOneItemPerPageAndKhacSoItIsNarrowerThanOneItemPerPage() {
        let pages = NotchPages(bar: ["a", "b", "c", "d", "e", "f"], overflow: ["x", "y", "z", "w", "v", "u", "t"])
        #expect(pages.items.count == 7)
        #expect(TabBarMetrics.width(count: pages.items.count) == CGFloat(7 * 30 + 6 * 6))
        #expect(TabBarMetrics.width(count: pages.items.count) < TabBarMetrics.width(count: pages.count) - 150, "the bar is a good deal shorter")
    }
}

// MARK: the grid

@Suite struct NotchMoreGridTests {
    func pages(_ ids: [ModuleID]) -> [NotchTab] {
        ids.map { NotchTab(id: $0, title: "Trang \($0.rawValue)", systemImage: "circle.fill", content: AnyView(EmptyView())) }
    }

    func host(_ ids: [ModuleID], open: @escaping (ModuleID) -> Void) -> (NSHostingView<AnyView>, NSWindow) {
        let view = MoreTabGrid(pages: pages(ids), open: open).frame(width: 556, height: 196, alignment: .top)
        let hosting = NSHostingView(rootView: AnyView(view))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 556, height: 196), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    @Test func theGridHasFourToARowAndGrowsByARowForEveryFourPages() {
        for (count, rows) in [(1, 1), (4, 1), (5, 2), (8, 2), (9, 3), (12, 3)] {
            let ids = (0..<count).map { ModuleID(stringLiteral: "p\($0)") }
            let (hosting, window) = host(ids) { _ in }
            defer { window.contentView = nil }
            let height = CGFloat(rows) * MoreTabGrid.cellHeight + CGFloat(rows - 1) * MoreTabGrid.spacing
            let fitting = NSHostingView(rootView: MoreTabGrid(pages: pages(ids)) { _ in }.frame(width: 556)).fittingSize
            #expect(abs(fitting.height - height) < 1, "\(count) pages: \(fitting.height) against \(height)")
            _ = hosting
        }
    }
}

// MARK: the real root view, drawn

/// The tab bar as the root view wires it, drawn offscreen in the classic look: thirteen pages with the placement they have by default, so
/// the bar is six pages and Khác. This is what proves the width of the slab's bar and what it marks, as the pieces above prove their parts.
@Suite struct NotchMoreRootRenderTests {
    let geometry = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())

    /// The root view drawn at the panel's size, open on `page`.
    func render(opening page: ModuleID) async throws -> NSBitmapImageRep {
        let harness = await harness()
        let model = NotchViewModel(
            scheduler: harness.scheduler, availableTabs: { [registry = harness.registry] in registry.pages.selectable }, delays: { (.zero, .zero) }
        )
        model.open(tab: page)
        try #require(model.displayState == .open(page))
        let view = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry)
            .frame(width: geometry.panelSize.width, height: geometry.panelSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    /// The row of the tab bar: under the top inset, as tall as an item.
    var barRows: Range<Int> { Int(geometry.openTopInset)..<Int(geometry.openTopInset + TabBarMetrics.iconSize.height) }

    func pixel(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .black
    }

    func isLit(_ color: NSColor) -> Bool { color.alphaComponent > 0.5 && max(color.redComponent, color.greenComponent, color.blueComponent) > 0.25 }

    /// Where the lit pixels of the bar's row begin and end.
    func litExtent(_ bitmap: NSBitmapImageRep) -> ClosedRange<Int>? {
        var xs: [Int] = []
        // (Not the notch's own edge, whose antialiasing is not black.)
        let inside = Int(geometry.panelSize.width - geometry.shapeSize(for: .open(nil)).width) / 2 + 8
        for x in inside..<(bitmap.pixelsWide - inside) where barRows.contains(where: { isLit(pixel(bitmap, x, $0)) }) { xs.append(x) }
        return xs.first.flatMap { first in xs.last.map { first...$0 } }
    }

    /// The cell of item `index` of the bar (`items` of them, centred on the notch), in x.
    func cell(_ index: Int, of items: Int) -> Range<Int> {
        let width = TabBarMetrics.width(count: items)
        let left = (geometry.panelSize.width - width) / 2 + CGFloat(index) * (TabBarMetrics.iconSize.width + TabBarMetrics.spacing)
        return Int(left)..<Int(left + TabBarMetrics.iconSize.width)
    }

    /// How many pixels of `cell` are the accent behind a selected item (a dim accent, mostly blue) or the badge's circle (the accent, bright).
    func accentPixels(_ bitmap: NSBitmapImageRep, in cell: Range<Int>, bright: Bool) -> Int {
        var count = 0
        for x in cell { for y in barRows {
            let color = pixel(bitmap, x, y)
            let strong = color.blueComponent > 0.85 && color.redComponent < 0.7
            let dim = color.blueComponent > 0.2 && color.blueComponent < 0.6 && color.blueComponent > 1.6 * color.greenComponent
            if bright ? strong : dim { count += 1 }
        } }
        return count
    }

    @Test func theBarIsSevenItemsWideNotThirteen() async throws {
        let bitmap = try await render(opening: "media")
        let extent = try #require(litExtent(bitmap))
        // Seven cells of 30 and six gaps of 6 are 246 pt; the glyphs do not reach the cells' edges. Thirteen would be 450.
        #expect((190...246).contains(extent.count), "the lit part of the bar is \(extent.count) pt wide")
        #expect(Double(extent.lowerBound + extent.upperBound) / 2 - geometry.panelSize.width / 2 < 3, "centred")
    }

    @Test func aPageInKhacMarksTheKhacItemAndBadgesItWhileAPageOnTheBarDoesNot() async throws {
        let inKhac = try await render(opening: "timer")
        let onBar = try await render(opening: "media")
        let khac = cell(6, of: 7)
        #expect(accentPixels(inKhac, in: khac, bright: false) > 150, "the accent behind the Khác item")
        #expect(accentPixels(inKhac, in: khac, bright: true) > 15, "and the badge, in its corner")
        #expect(accentPixels(onBar, in: khac, bright: false) < 10 && accentPixels(onBar, in: khac, bright: true) < 3, "a page on the bar leaves Khác plain")
        // The page on the bar is the one marked, and the others are not.
        #expect(accentPixels(onBar, in: cell(1, of: 7), bright: false) > 150)
        #expect(accentPixels(inKhac, in: cell(1, of: 7), bright: false) < 10)
        #expect(accentPixels(inKhac, in: cell(5, of: 7), bright: false) < 10, "nor the page next to Khác")
    }

    @Test func theGridOfKhacMarksTheItemWithNoBadge() async throws {
        let grid = try await render(opening: NotchPages.moreID)
        let khac = cell(6, of: 7)
        #expect(accentPixels(grid, in: khac, bright: false) > 150)
        #expect(accentPixels(grid, in: khac, bright: true) < 3, "nothing to badge it with: it is the grid")
    }
}
