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

    /// Builds it and lays it out. `tilesDelay` is how long the open notch keeps its own glass before the tiles replace it.
    static func make(
        look: NotchLook, clarity: NotchGlassClarity = .balanced, shape: NotchGlassShape = .slab, tinted: Bool = false, tabs: Int = 1,
        tilesDelay: Duration = NotchGlassPlan.tilesDelay
    ) async throws -> OpenNotch {
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
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
            rootView: NotchRootView(
                model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme, tilesDelay: tilesDelay
            )
        )
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        for _ in 0..<50 where frame.value == nil {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        hosting.layoutSubtreeIfNeeded()
        return OpenNotch(hosting: hosting, window: window, frame: frame, geometry: geometry, model: model, settings: harness.settings)
    }

    func close() { window.contentView = nil }

    /// Lets the run loop turn so SwiftUI applies what changed, then lays the view out.
    func settle(_ milliseconds: Int = 150) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
        hosting.layoutSubtreeIfNeeded()
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
        #expect(abs(tiled.minX - (slab.minX + pad)) < 0.01 && abs(tiled.width - (slab.width - 2 * pad)) < 0.01)
        #expect(abs(tiled.maxY - (slab.maxY - pad)) < 0.01, "the notch is the size it was")
    }

    @Test func withOneTabThereIsNoCapsuleAndTheTileIsStillAroundTheContent() async throws {
        let pad = NotchGlassPlan.tilePadding
        let slab = try await tabFrame(shape: .slab, tabs: 1)
        let tiled = try await tabFrame(shape: .tiles, tabs: 1)
        #expect(abs(tiled.minY - (slab.minY + pad)) < 0.01 && abs(tiled.maxY - (slab.maxY - pad)) < 0.01)
        #expect(abs(tiled.width - (slab.width - 2 * pad)) < 0.01)
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
        try await notch.settle()
        #expect(notch.frame.plan?.notch?.glass == Glass.clear, "the clarity, live")
        #expect(try #require(notch.frame.value) == slab, "and nothing moved")

        notch.settings.set(.tiles, for: InterfaceSettings.glassShape)
        try await notch.settle()
        #expect(notch.frame.plan?.shape == .tiles)
        let tiled = try #require(notch.frame.value)
        #expect(abs(tiled.minX - (slab.minX + pad)) < 0.01, "the content is in its tile now: \(tiled)")

        notch.settings.set(.slab, for: InterfaceSettings.glassShape)
        try await notch.settle()
        #expect(notch.frame.plan?.tiles == nil)
        #expect(try #require(notch.frame.value) == slab, "and back")
    }

    // MARK: the open notch's glass gives way to the tiles once it has grown

    @Test func theOpenNotchKeepsItsOwnGlassWhileItGrows() async throws {
        // A delay no run of the test comes near: the notch is still "growing" however loaded the machine is.
        let notch = try await OpenNotch.make(look: .liquidGlass, shape: .tiles, tabs: 2, tilesDelay: .seconds(30))
        defer { notch.close() }
        try await notch.settle(300)
        #expect(notch.frame.plan?.tiles?.isShown == false, "growing: not the tiles yet")
        #expect(notch.frame.plan?.panelHasGlass == true, "the notch's own glass")
        #expect(notch.frame.plan?.veil == NotchGlassPlan.hitOpacity)
    }

    @Test func onceItHasGrownTheTilesTakeOver() async throws {
        let notch = try await OpenNotch.make(look: .liquidGlass, shape: .tiles, tabs: 2, tilesDelay: .milliseconds(30))
        defer { notch.close() }
        var shown = false
        for _ in 0..<100 where !shown {
            try await notch.settle(30)
            shown = notch.frame.plan?.tiles?.isShown == true
        }
        #expect(shown, "grown: the tiles")
        #expect(notch.frame.plan?.panelHasGlass == false)
    }

    @Test func theNotchsGlassIsBackTheMomentItIsNotOpenAndTheTabIsNotRebuilt() async throws {
        for shape in NotchGlassShape.allCases {
            let notch = try await OpenNotch.make(look: .liquidGlass, shape: shape, tabs: 2, tilesDelay: .milliseconds(20))
            defer { notch.close() }
            try await notch.settle(600)
            if shape == .tiles { #expect(notch.frame.plan?.panelHasGlass == false, "settled tiles") }
            #expect(notch.frame.appeared == 1, "\(shape): it appeared once")
            // A toast covers the tab, which stays alive under it, hidden.
            notch.model.showToast(AnyView(Color.clear), duration: .seconds(60))
            try await notch.settle()
            #expect(notch.model.displayState == .toast)
            #expect(notch.frame.plan?.panelHasGlass == true, "\(shape): the notch's glass is back for the toast")
            #expect(notch.frame.plan?.tiles?.isShown != true)
            notch.model.open(tab: "probe")
            try await notch.settle(800)
            #expect(notch.model.displayState == .open("probe"))
            #expect(notch.frame.appeared == 1, "\(shape): the toast and back did not rebuild the tab (\(notch.frame.appeared))")
            if shape == .tiles { #expect(notch.frame.plan?.tiles?.isShown == true, "and the tiles are back once it has grown") }
        }
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
