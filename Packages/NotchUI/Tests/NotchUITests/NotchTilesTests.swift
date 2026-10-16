import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

// MARK: the open notch, hosted

private final class ProbeFrame {
    var value: CGRect?
    /// How many times the tab's content appeared: it must not appear again when the notch goes to a toast and back.
    var appeared = 0
    /// The glass plan the tab's content last saw in its environment, which is what the notch is drawn from.
    var plan: NotchGlassPlan?
}

/// A tab's content that reports where it is, that it appeared, and the glass plan around it.
private struct TabProbe: View {
    let frame: ProbeFrame
    @Environment(\.notchGlassPlan) private var plan

    var body: some View {
        let _ = (frame.plan = plan)
        Color.clear
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [frame] in frame.value = $0 }
            .onAppear { [frame] in frame.appeared += 1 }
    }
}

private final class ProbeModule: FeatureModule {
    let descriptor: ModuleDescriptor
    let frame: ProbeFrame?
    init(_ id: ModuleID, order: Int, frame: ProbeFrame?) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: true, order: order)
        self.frame = frame
    }
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: descriptor.displayName, systemImage: "circle", preferredHeight: 190,
            content: frame.map { AnyView(TabProbe(frame: $0)) } ?? AnyView(Color.clear)
        )
    }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

/// An open notch of the real root view hosted in a window that is never shown, with a tab ("probe") whose content reports its
/// frame and its glass plan, and as many more tabs as asked for. Its settings are the ones of its theme, so they can be changed
/// while it is hosted.
private struct OpenNotch {
    let hosting: NSHostingView<NotchRootView>
    let window: NSWindow
    let frame: ProbeFrame
    let geometry: NotchGeometry
    let model: NotchViewModel
    let settings: SettingsStore
    let harness: RegistryHarness
    let theme: NotchTheme

    /// Builds it and lays it out.
    static func make(
        look: NotchLook, clarity: NotchGlassClarity = .balanced, shape: NotchGlassShape = .slab, tinted: Bool = false, tabs: Int = 1
    ) async throws -> OpenNotch {
        // As the window controller makes it: with tiles the open notch is taller by their chrome (`NotchLayoutConfig(settings:)`).
        let geometry = NotchGeometry(
            screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(opensAsTiles: look == .liquidGlass && shape == .tiles)
        )
        let frame = ProbeFrame()
        let modules = [ProbeModule("probe", order: 0, frame: frame)]
            + (1..<max(tabs, 1)).map { ProbeModule(ModuleID(stringLiteral: "other\($0)"), order: $0, frame: nil) }
        let harness = RegistryHarness(modules)
        await harness.registry.bootstrap()
        harness.settings.set(look, for: InterfaceSettings.look)
        harness.settings.set(clarity, for: InterfaceSettings.glassClarity)
        harness.settings.set(shape, for: InterfaceSettings.glassShape)
        harness.settings.set(tinted, for: InterfaceSettings.glassTint)
        let theme = NotchTheme(settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let model = NotchViewModel(
            scheduler: harness.scheduler, availableTabs: { [registry = harness.registry] in registry.tabs.map(\.id) }, delays: { (.zero, .zero) }
        )
        model.open(tab: "probe")
        try #require(model.displayState == .open("probe"))
        let hosting = NSHostingView(
            rootView: NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
        )
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        let notch = OpenNotch(
            hosting: hosting, window: window, frame: frame, geometry: geometry, model: model, settings: harness.settings, harness: harness,
            theme: theme
        )
        try await notch.wait("the tab was laid out") { frame.value != nil }
        try await notch.settle()
        return notch
    }

    func close() { window.contentView = nil }

    /// What the window controller does when the settings change the geometry: a root view of the new one, and a panel of its size.
    func reshape(opensAsTiles: Bool) {
        let new = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(opensAsTiles: opensAsTiles))
        hosting.rootView = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: new, theme: theme)
        window.setContentSize(new.panelSize)
        hosting.frame = CGRect(origin: .zero, size: new.panelSize)
    }

    /// Waits for `condition`, which is polled every 10 ms (the main actor is free while it sleeps, so SwiftUI applies what changed), and
    /// lays the view out each time; up to ten seconds. Every positive assertion waits for what it expects, never for a stretch of the
    /// clock.
    func wait(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            hosting.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        hosting.layoutSubtreeIfNeeded()
        try #require(condition(), "gave up waiting: \(what)")
    }

    /// Waits until the tab's frame has not moved for 100 ms: with tiles the notch springs out of its body as it opens, and a shape
    /// chosen while it is open springs out the same way.
    func settle() async throws {
        var last: CGRect?
        var still = 0
        for _ in 0..<1000 {
            hosting.layoutSubtreeIfNeeded()
            if let value = frame.value, value == last { still += 1 } else { still = 0 }
            if still >= 10 { return }
            last = frame.value
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(Bool(false), "gave up waiting: the tab to settle")
    }

    /// Lets the run loop turn a few times, for an assertion that nothing happened (it follows a wait for what was to happen).
    func turn() async throws {
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(10))
            hosting.layoutSubtreeIfNeeded()
        }
    }

    /// The same point on the screen of `NotchGeometryTests.macBook14`, which is what the pointer tracking works in.
    func screenPoint(_ point: CGPoint) -> CGPoint {
        let panel = geometry.panelFrame(in: NotchGeometryTests.macBook14.frame)
        return CGPoint(x: panel.minX + point.x, y: panel.maxY - point.y)
    }
}

/// Where the open notch puts its tab bar and content when its panel has no glass of its own.
@Suite struct NotchTilesLayoutTests {
    let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())

    func tabFrame(look: NotchLook = .liquidGlass, clarity: NotchGlassClarity = .balanced, shape: NotchGlassShape = .slab, tabs: Int) async throws -> CGRect {
        let notch = try await OpenNotch.make(look: look, clarity: clarity, shape: shape, tabs: tabs)
        defer { notch.close() }
        return try #require(notch.frame.value)
    }

    @Test func theTabStartsUnderTheNotchsBodyOnTheSlabWithOneTab() async throws {
        let frame = try await tabFrame(tabs: 1)
        #expect(abs(frame.minY - geometry.notchSize.height) < 0.01, "\(frame)")
    }

    @Test func theContentSitsInATileInsetByTheTabBarsCapsuleTheGapAndThePadding() async throws {
        let gap = NotchGlassPlan.tileGap, pad = NotchGlassPlan.tilePadding
        let capsule = 24 + 2 * NotchGlassPlan.tabBarInset.height
        let slab = try await tabFrame(shape: .slab, tabs: 2)
        let tiled = try await tabFrame(shape: .tiles, tabs: 2)
        // The slab: the tab bar's 24 pt and 6 below it, then the tab. Tiles: the capsule, the gap, then the tile's padding.
        #expect(abs(slab.minY - (geometry.notchSize.height + 24 + 6)) < 0.01, "\(slab)")
        #expect(abs(tiled.minY - (geometry.notchSize.height + capsule + gap + pad)) < 0.01, "\(tiled)")
        // And the tab has the room it has in one piece, to the point: the notch is taller for the tiles' chrome.
        #expect(abs(tiled.minX - slab.minX) < 0.01 && abs(tiled.width - slab.width) < 0.01, "\(slab) \(tiled)")
        #expect(abs(tiled.height - slab.height) < 0.01, "\(slab) \(tiled)")
    }

    @Test func withOneTabThereIsNoCapsuleAndTheTileIsStillAroundTheContentWhichHasTheSameRoom() async throws {
        let pad = NotchGlassPlan.tilePadding
        let slab = try await tabFrame(shape: .slab, tabs: 1)
        let tiled = try await tabFrame(shape: .tiles, tabs: 1)
        #expect(abs(tiled.minY - (slab.minY + pad)) < 0.01, "the tile's padding above it")
        #expect(abs(tiled.width - slab.width) < 0.01 && abs(tiled.height - slab.height) < 0.01 && abs(tiled.minX - slab.minX) < 0.01)
    }

    @Test func clarityMovesNothingOnEitherShape() async throws {
        for shape in NotchGlassShape.allCases {
            let reference = try await tabFrame(clarity: .balanced, shape: shape, tabs: 2)
            #expect(try await tabFrame(clarity: .clear, shape: shape, tabs: 2) == reference, "\(shape)")
        }
    }

    @Test func theClassicNotchIsTheSameWhateverTheGlassSettingsAre() async throws {
        for tabs in [1, 2] {
            let reference = try await tabFrame(look: .classic, tabs: tabs)
            for (clarity, shape) in [(NotchGlassClarity.clear, NotchGlassShape.tiles), (.balanced, .tiles), (.clear, .slab)] {
                #expect(try await tabFrame(look: .classic, clarity: clarity, shape: shape, tabs: tabs) == reference, "\(tabs) tabs \(clarity) \(shape)")
            }
        }
    }

    // MARK: switching while it is open

    @Test func changingTheShapeOrTheClarityUpdatesTheOpenNotchWithoutARelaunch() async throws {
        let notch = try await OpenNotch.make(look: .liquidGlass, tabs: 2)
        defer { notch.close() }
        let pad = NotchGlassPlan.tilePadding
        let slab = try #require(notch.frame.value)
        #expect(notch.frame.plan?.tiles == nil)
        #expect(notch.frame.plan?.notch?.glass == Glass.regular)

        notch.settings.set(.clear, for: InterfaceSettings.glassClarity)
        try await notch.wait("the clear glass") { notch.frame.plan?.notch?.glass == Glass.clear }
        #expect(try #require(notch.frame.value) == slab, "the clarity, live, and nothing moved")

        notch.settings.set(.tiles, for: InterfaceSettings.glassShape)
        notch.reshape(opensAsTiles: true)
        try await notch.wait("the tiles") { notch.frame.plan?.shape == .tiles && notch.frame.value?.minY != slab.minY }
        try await notch.settle()
        let tiled = try #require(notch.frame.value)
        #expect(abs(tiled.minY - (slab.minY + NotchGlassPlan.tileGap + pad)) < 0.01, "the content is in its tile now, under the capsule: \(tiled)")
        #expect(abs(tiled.width - slab.width) < 0.01 && abs(tiled.height - slab.height) < 0.01, "with the room it had: \(slab) \(tiled)")

        notch.settings.set(.slab, for: InterfaceSettings.glassShape)
        notch.reshape(opensAsTiles: false)
        try await notch.wait("the slab again") { notch.frame.plan?.tiles == nil && notch.frame.value == slab }
        #expect(try #require(notch.frame.value) == slab, "and back")
    }

    // MARK: the glass is the notch's in every state, and the tiles come out of it

    @Test func theOpenNotchHasNoGlassOfItsOwnFromTheStartAndTheTilesAreGlass() async throws {
        let notch = try await OpenNotch.make(look: .liquidGlass, shape: .tiles, tabs: 2)
        defer { notch.close() }
        // No delay: the plan the tab sees, the first one, already has the notch's glass gone and the tiles in.
        let plan = try #require(notch.frame.plan)
        #expect(plan.tiles?.isOpen == true)
        #expect(!plan.panelHasGlass)
        #expect(plan.tiles?.tabBar.glass == Glass.regular && plan.tiles?.content.glass == Glass.regular)
        #expect(plan.veil == NotchGlassPlan.hitOpacity)
    }

    @Test func theNotchsGlassIsBackTheMomentAToastCoversTheTabAndTheTabIsNotRebuilt() async throws {
        for shape in NotchGlassShape.allCases {
            let notch = try await OpenNotch.make(look: .liquidGlass, shape: shape, tabs: 2)
            defer { notch.close() }
            #expect(notch.frame.appeared == 1, "\(shape): it appeared once")
            // A toast covers the tab, which stays alive under it, hidden.
            notch.model.showToast(AnyView(Color.clear), duration: .seconds(60))
            try await notch.wait("the toast's glass") { notch.model.displayState == .toast && notch.frame.plan?.panelHasGlass == true }
            #expect(notch.frame.plan?.tiles?.isOpen != true)
            notch.model.open(tab: "probe")
            try await notch.wait("the open notch again") { notch.model.displayState == .open("probe") && notch.frame.plan?.tiles?.isOpen != false }
            if shape == .tiles { try await notch.wait("no glass of its own") { notch.frame.plan?.panelHasGlass == false } }
            try await notch.turn()
            #expect(notch.frame.appeared == 1, "\(shape): the toast and back did not rebuild the tab (\(notch.frame.appeared))")
        }
    }

    @Test func theTabsKeepTheirViewsWhateverTheNotchIsDoingWithTiles() async throws {
        let notch = try await OpenNotch.make(look: .liquidGlass, shape: .tiles, tabs: 2)
        defer { notch.close() }
        // A look change and back (what the glass settings are next to) is the one thing that rebuilds; a clarity change is not.
        notch.settings.set(.clear, for: InterfaceSettings.glassClarity)
        try await notch.wait("clear") { notch.frame.plan?.tiles?.content.glass == Glass.clear }
        notch.settings.set(.balanced, for: InterfaceSettings.glassClarity)
        try await notch.wait("balanced") { notch.frame.plan?.tiles?.content.glass == Glass.regular }
        try await notch.turn()
        #expect(notch.frame.appeared == 1, "a change of clarity does not rebuild the tab")
    }

    // MARK: the gaps are part of the notch

    /// A point in the gap between the tab bar's capsule and the content's tile, in the open notch with tiles.
    fileprivate func gapPoint(_ notch: OpenNotch) throws -> CGPoint {
        let content = try #require(notch.frame.value)
        return CGPoint(x: content.midX, y: content.minY - NotchGlassPlan.tilePadding - NotchGlassPlan.tileGap / 2)
    }

    @Test func aPointInTheGapIsInsideTheNotchForTheHoverTrackerAndTheClickOutsideCheck() async throws {
        let notch = try await OpenNotch.make(look: .liquidGlass, shape: .tiles, tabs: 2)
        defer { notch.close() }
        let gap = try gapPoint(notch)
        let screen = notch.screenPoint(gap)
        let frame = NotchGeometryTests.macBook14.frame
        // The pointer tracking works on the notch's rect, not on what is drawn, so the gap is inside it: hover keeps the notch open
        // and a press there is not a click outside.
        let state = notch.model.displayState
        #expect(state == .open("probe"))
        #expect(notch.geometry.pointerZone(at: screen, state: state, contentHeight: 190, in: frame) == .notch)
        // And a point beside the notch is outside, so the test can tell.
        #expect(notch.geometry.pointerZone(at: notch.screenPoint(CGPoint(x: 5, y: gap.y)), state: state, contentHeight: 190, in: frame) == .outside)
    }

    /// The alpha of the pixel at `point` (from the panel's top left) of what the hosting view draws by itself. A window that is not
    /// opaque lets a click fall through to the app behind where it is fully transparent, so this is what a click in a gap depends
    /// on. (The hosting view's own `hitTest` hands itself back for every point of its bounds, so it cannot tell.) Glass is not drawn
    /// offscreen, so what shows is what SwiftUI itself draws: the veil.
    fileprivate func alpha(_ notch: OpenNotch, at point: CGPoint) throws -> Double {
        let bounds = notch.hosting.bounds
        let rep = try #require(notch.hosting.bitmapImageRepForCachingDisplay(in: bounds))
        notch.hosting.cacheDisplay(in: bounds, to: rep)
        let scale = Double(rep.pixelsWide) / bounds.width
        let color = try #require(rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
        return Double(color.alphaComponent)
    }

    @Test func aPointInTheGapIsNotFullyTransparentSoAClickThereStaysInTheWindowAndBesideTheNotchItIs() async throws {
        let notch = try await OpenNotch.make(look: .liquidGlass, shape: .tiles, tabs: 2)
        defer { notch.close() }
        let gap = try gapPoint(notch)
        // (That it is too faint to see is the plan's test: `hitOpacity` is under three levels of 255.)
        #expect(try alpha(notch, at: gap) > 0, "the veil is there, in the gap too")
        #expect(try alpha(notch, at: CGPoint(x: 5, y: gap.y)) == 0, "outside the notch's shape the panel is transparent, which is what the test can tell")
    }

    @Test func theGapsOfTheClassicNotchAreBlackWhateverIsSet() async throws {
        let classic = try await OpenNotch.make(look: .classic, clarity: .clear, shape: .tiles, tabs: 2)
        defer { classic.close() }
        #expect(try alpha(classic, at: gapPoint(classic)) > 0.99)
    }
}

/// Where the tiles are, as numbers (`NotchTilesLayout`): the collapsed notch's body when the notch is not open, the tab page's rects
/// when it is, and the tab bar's width that the capsule is made from.
@Suite struct NotchTilesLayoutMathTests {
    let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())

    var openSize: CGSize { geometry.shapeSize(for: .open(nil), contentHeight: NotchTab.defaultHeight) }

    func open(tabs: Int) -> NotchTilesLayout {
        NotchTilesLayout.open(
            shapeSize: openSize, topInset: geometry.openTopInset, topRadius: geometry.cornerRadii(for: .open(nil)).top, tabCount: tabs
        )
    }

    func rest(_ state: NotchState = .compact, hasTabBar: Bool = true) -> NotchTilesLayout {
        NotchTilesLayout.rest(collapsedSize: geometry.shapeSize(for: state), topRadius: geometry.cornerRadii(for: state).top, hasTabBar: hasTabBar)
    }

    // MARK: open

    @Test func theOpenTilesAreTheTabPagesRectsWithTheCapsuleOverTheTile() {
        let pad = NotchTokens.padding, gap = NotchGlassPlan.tileGap
        let layout = open(tabs: 3)
        let bar = layout.tabBar
        #expect(bar?.size == CGSize(width: TabBarMetrics.width(count: 3) + 16, height: 30))
        #expect(bar?.top == geometry.notchSize.height, "under the notch's body")
        #expect(layout.content.top == geometry.notchSize.height + 30 + gap)
        #expect(layout.content.size.width == openSize.width - 2 * (8 + pad - NotchGlassPlan.tilePadding), "the tile reaches the padding further out than the content, which is inside the ears and the padding")
        #expect(layout.content.top + layout.content.size.height == openSize.height - pad, "the padding above the notch's bottom")
        // Concentric corners, so the tile's radius is the notch's less the padding.
        #expect(NotchGlassPlan.concentricRadius(outer: geometry.cornerRadii(for: .open(nil)).bottom, inset: pad) == 10)
    }

    @Test func withOneTabThereIsNoCapsuleAndTheTileStartsUnderTheNotchsBody() {
        let layout = open(tabs: 1)
        #expect(layout.tabBar == nil)
        #expect(layout.content.top == geometry.notchSize.height)
        #expect(layout.content.size.height == openSize.height - NotchTokens.padding - geometry.notchSize.height)
        #expect(open(tabs: 0).tabBar == nil)
    }

    @Test func theCapsuleIsAsWideAsTheRealTabBarPlusItsInset() async throws {
        for count in [2, 3, 5, 8] {
            let tabs = (0..<count).map { NotchTab(id: ModuleID(stringLiteral: "t\($0)"), title: "T", systemImage: "circle", content: AnyView(EmptyView())) }
            let hosting = NSHostingView(rootView: TabBar(tabs: tabs, selected: nil) { _ in })
            #expect(abs(hosting.fittingSize.width - TabBarMetrics.width(count: count)) < 0.5, "\(count) tabs")
            #expect(abs(hosting.fittingSize.height - TabBarMetrics.iconSize.height) < 0.5)
        }
    }

    // MARK: rest

    @Test func theRestingTilesAreTheBodyOfTheCollapsedNotchOfEachStateWithTheCapsuleKept() {
        for state in [NotchState.closed, .compact] {
            let collapsed = geometry.shapeSize(for: state)
            let ears = 2 * geometry.cornerRadii(for: state).top
            let layout = rest(state)
            let body = NotchTilesLayout.Tile(size: CGSize(width: collapsed.width - ears, height: collapsed.height), top: 0)
            #expect(layout.content == body, "\(state)")
            #expect(layout.tabBar == body, "the capsule starts from the same body")
            #expect(rest(state, hasTabBar: false).tabBar == nil)
        }
    }

    @Test func theRestingTilesAreInsideTheCollapsedNotchSoTheirGlassIsInsideItsOwn() {
        for state in [NotchState.closed, .compact] {
            let collapsed = geometry.shapeSize(for: state)
            for tile in [rest(state).content, rest(state).tabBar!] {
                #expect(tile.size.width <= collapsed.width && tile.size.height <= collapsed.height)
                #expect(tile.top >= 0 && tile.top + tile.size.height <= collapsed.height)
            }
        }
        // With a hardware notch the closed notch's body is the cutout's width, which is where the tiles start.
        #expect(rest(.closed).content.size.width == geometry.notchSize.width)
    }

    // MARK: when a tile is glass

    @Test func progressIsZeroAtTheRestRectAndOneAtTheTabPagesRectInWhicheverDimensionTravelsMost() {
        let rest = rest(), end = open(tabs: 2)
        #expect(NotchTilesLayout.progress(of: rest.content.size, from: rest.content.size, to: end.content.size) == 0)
        #expect(NotchTilesLayout.progress(of: end.content.size, from: rest.content.size, to: end.content.size) == 1)
        let half = CGSize(width: (rest.content.size.width + end.content.size.width) / 2, height: (rest.content.size.height + end.content.size.height) / 2)
        #expect(abs(NotchTilesLayout.progress(of: half, from: rest.content.size, to: end.content.size) - 0.5) < 0.001)
        // The capsule narrows as it comes out: its width travels backwards and its height does not, and it is still 0 to 1.
        let bar = (rest.tabBar!.size, end.tabBar!.size)
        #expect(NotchTilesLayout.progress(of: bar.0, from: bar.0, to: bar.1) == 0)
        #expect(NotchTilesLayout.progress(of: bar.1, from: bar.0, to: bar.1) == 1)
        // With nothing to travel in a dimension it is ignored, and a tile that overshoots is past 1.
        #expect(NotchTilesLayout.progress(of: CGSize(width: 5, height: 5), from: CGSize(width: 5, height: 5), to: CGSize(width: 5, height: 5)) == 0)
        #expect(NotchTilesLayout.progress(of: CGSize(width: end.content.size.width + 4, height: end.content.size.height), from: rest.content.size, to: end.content.size) > 1)
    }

    @Test func aTileIsBackInTheNotchsBodyOnlyWhenItIsAtItsRestRectOrPastIt() {
        let rest = rest(), end = open(tabs: 2)
        for tile in [(rest.content, end.content), (rest.tabBar!, end.tabBar!)] {
            func back(_ progress: CGFloat) -> Bool {
                let size = CGSize(
                    width: tile.0.size.width + progress * (tile.1.size.width - tile.0.size.width),
                    height: tile.0.size.height + progress * (tile.1.size.height - tile.0.size.height)
                )
                return NotchTilesLayout.isBack(size: size, rest: tile.0.size, final: tile.1.size)
            }
            #expect(back(0) && back(NotchTilesLayout.backWithin) && back(-0.1), "at the rest rect, or under it as the spring overshoots")
            #expect(!back(NotchTilesLayout.backWithin * 3) && !back(0.5) && !back(1), "not while it still has a way to go")
        }
        #expect(NotchTilesLayout.backWithin > 0 && NotchTilesLayout.backWithin < 0.1, "a tile is taken out when it is inside the pill")
    }

    @Test func theTilesStartAtTheCollapsedNotchAndEndAtTheTabPagesRects() {
        // What the animation runs between: the layout before the notch opens and the one after, on the same tiles.
        let start = rest(), end = open(tabs: 2)
        #expect(start != end)
        #expect(start.content.size.width < end.content.size.width && start.content.size.height < end.content.size.height)
        #expect(start.content.top == 0 && end.content.top > 0)
        #expect(start.tabBar?.size.width ?? 0 > end.tabBar?.size.width ?? .infinity, "the capsule narrows as it comes out")
    }

    @Test func aTabOfAnotherHeightMovesTheFinalRectsSoTheAnimationFollowsIt() {
        let tall = NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: 240), topInset: geometry.openTopInset, topRadius: 8, tabCount: 2
        )
        let short = NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: 120), topInset: geometry.openTopInset, topRadius: 8, tabCount: 2
        )
        #expect(tall != short, "the animation is keyed on the layout, which differs")
        #expect(tall.content.size.height - short.content.size.height == 120)
        #expect(tall.tabBar == short.tabBar)
    }
}
