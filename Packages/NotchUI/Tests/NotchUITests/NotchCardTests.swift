import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The card modifier (`notchCard`), the sample strip, the tiles and the dimming layer of U3c. What a card is made of is a value
/// (`NotchCardPlan`); the classic wash is compared pixel for pixel with the expression it replaces, on views with no glass in
/// them (glass is not drawn offscreen, and a render of it is not stable); where the sample strip is comes from layout.
@Suite struct NotchCardTests {
    let accent = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.9)
    let glass = NotchSurface.liquidGlass(tinted: false)

    func resolve(
        _ surface: NotchSurface, _ switches: NotchGlassSwitches, fill: Double = 0.08, selected: Bool = false, interactive: Bool = false,
        onDesktop: Bool = false
    ) -> NotchCardPlan {
        NotchCardPlan.resolve(
            surface: surface, switches: switches, accent: accent, fill: fill, selected: selected, interactive: interactive, onDesktop: onDesktop
        )
    }

    /// Every combination of the switches, for the tests that say "whatever they are".
    var everySwitch: [NotchGlassSwitches] {
        var all: [NotchGlassSwitches] = []
        for variant in NotchGlassVariant.allCases {
            for panel in NotchGlassPanel.allCases {
                for scheme in NotchGlassScheme.allCases {
                    for selected in NotchGlassSelected.allCases {
                        for sample in [false, true] {
                            all.append(
                                NotchGlassSwitches(variant: variant, panel: panel, dim: 0.3, scheme: scheme, sample: sample, selected: selected)
                            )
                        }
                    }
                }
            }
        }
        return all
    }

    // MARK: what a card is made of

    @Test func onTheClassicNotchACardIsTheWashWhateverTheSwitchesSayAndWhereverItIs() {
        for surface in [NotchSurface.solid, .material] {
            for switches in everySwitch {
                for onDesktop in [false, true] {
                    #expect(resolve(surface, switches, onDesktop: onDesktop) == NotchCardPlan(fill: .wash(0.08)))
                    #expect(resolve(surface, switches, fill: 0.14, interactive: true, onDesktop: onDesktop) == NotchCardPlan(fill: .wash(0.14)))
                    #expect(resolve(surface, switches, selected: true, onDesktop: onDesktop) == NotchCardPlan(fill: .selectedWash(rim: false)))
                }
            }
        }
    }

    @Test func glassIsNeverNestedInGlassACardInsideTheNotchsGlassOrATileIsAWashOrAWhiteTile() {
        for switches in everySwitch {
            for selected in [false, true] {
                for interactive in [false, true] {
                    let card = resolve(glass, switches, selected: selected, interactive: interactive, onDesktop: false)
                    if case .glass = card.fill { Issue.record("glass in glass for \(switches), selected \(selected)") }
                }
            }
            #expect(resolve(glass, switches) == NotchCardPlan(fill: .wash(0.08)))
            #expect(resolve(glass, switches, fill: 0.05) == NotchCardPlan(fill: .wash(0.05)))
            #expect(
                resolve(glass, switches, selected: true)
                    == NotchCardPlan(fill: switches.selected == .white ? .onTile : .selectedWash(rim: true))
            )
        }
    }

    @Test func onTheDesktopACardIsGlassOnlyWithTilesAndOfTheNotchsVariant() {
        let regular = NotchGlassSwitches(variant: .regular, panel: .tiles)
        let clear = NotchGlassSwitches(variant: .clear, panel: .tiles)
        #expect(resolve(glass, regular, onDesktop: true) == NotchCardPlan(fill: .glass(Glass.regular)))
        #expect(resolve(glass, clear, onDesktop: true) == NotchCardPlan(fill: .glass(Glass.clear)))
        #expect(resolve(glass, clear, onDesktop: true) != NotchCardPlan(fill: .glass(Glass.regular)))
        // Whatever tint the notch has, a plain card has none of its own.
        #expect(resolve(.liquidGlass(tinted: true), clear, onDesktop: true) == NotchCardPlan(fill: .glass(Glass.clear)))
        // With the slab nothing is on the desktop, and the wash it was.
        for variant in NotchGlassVariant.allCases {
            #expect(resolve(glass, NotchGlassSwitches(variant: variant, panel: .slab), onDesktop: true) == NotchCardPlan(fill: .wash(0.08)))
        }
    }

    @Test func aGlassCardThatIsAControlIsInteractive() {
        let clear = NotchGlassSwitches(variant: .clear, panel: .tiles)
        #expect(resolve(glass, clear, interactive: true, onDesktop: true) == NotchCardPlan(fill: .glass(Glass.clear.interactive())))
        #expect(resolve(glass, clear, interactive: true, onDesktop: true) != resolve(glass, clear, onDesktop: true))
        #expect(
            resolve(glass, NotchGlassSwitches(panel: .tiles), interactive: true, onDesktop: true)
                == NotchCardPlan(fill: .glass(Glass.regular.interactive()))
        )
    }

    @Test func aSelectedChipOnTheDesktopIsGlassTintedWithTheAccentOrAWhiteTileWithADarkGlyph() {
        let tint = accent.opacity(NotchCardPlan.selectedTintOpacity)
        for variant in NotchGlassVariant.allCases {
            let tinted = NotchGlassSwitches(variant: variant, panel: .tiles, selected: .tint)
            #expect(resolve(glass, tinted, selected: true, onDesktop: true) == NotchCardPlan(fill: .glass(variant.glass.tint(tint))))
            #expect(
                resolve(glass, tinted, selected: true, interactive: true, onDesktop: true)
                    == NotchCardPlan(fill: .glass(variant.glass.tint(tint).interactive()))
            )

            let white = NotchGlassSwitches(variant: variant, panel: .tiles, selected: .white)
            #expect(resolve(glass, white, selected: true, onDesktop: true) == NotchCardPlan(fill: .onTile))
            #expect(resolve(glass, white, selected: true, interactive: true, onDesktop: true) == NotchCardPlan(fill: .onTile))
            // The switch is only for what is selected.
            #expect(resolve(glass, white, onDesktop: true) == NotchCardPlan(fill: .glass(variant.glass)))
        }
        #expect(NotchCardPlan.selectedTintOpacity > NotchTokens.glassTintOpacity, "it marks a state, so it is stronger than the notch's hint")
        #expect(NotchCardPlan.selectedTintOpacity < 1)
    }

    @Test func theWhiteSelectionAppliesOnTheSlabToo() {
        #expect(resolve(glass, NotchGlassSwitches(panel: .slab, selected: .white), selected: true) == NotchCardPlan(fill: .onTile))
        #expect(resolve(glass, NotchGlassSwitches(panel: .slab, selected: .tint), selected: true) == NotchCardPlan(fill: .selectedWash(rim: true)))
    }

    // MARK: concentric corners

    @Test func anInnerRadiusIsTheOuterOneLessTheGapBetweenThem() {
        #expect(NotchCardPlan.concentricRadius(outer: 24, inset: 14) == 10)
        #expect(NotchCardPlan.concentricRadius(outer: 10, inset: 4) == 6)
        #expect(NotchCardPlan.concentricRadius(outer: 6, inset: 14) == 0, "never negative")
    }

    @Test func theSampleCardsRadiusIsTheOpenNotchsBottomRadiusLessItsPadding() {
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let outer = geometry.cornerRadii(for: .open(nil)).bottom
        #expect(outer == 24)
        #expect(NotchTokens.padding == 14)
        #expect(NotchCardPlan.concentricRadius(outer: outer, inset: NotchTokens.padding) == 10)
    }

    // MARK: the classic wash is the expression it replaces

    func pixels(_ view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view.frame(width: 120, height: 80))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return try #require(bitmap.representation(using: .tiff, properties: [:]))
    }

    /// A black notch with a 80 x 40 box on it, dressed by `dress`.
    func box<Dressed: View>(_ dress: (AnyView) -> Dressed) -> some View {
        ZStack {
            Color.black
            dress(AnyView(Color.clear.frame(width: 80, height: 40)))
        }
    }

    @Test func onTheClassicNotchNotchCardIsPixelForPixelTheWashItReplaces() throws {
        try NotchLookState.$current.withValue(NotchLookState()) {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            let bare = try pixels(box { $0 })
            let today = try pixels(box { $0.background(NotchTokens.fill(0.08), in: shape) })
            let card = try pixels(box { $0.notchCard(in: shape) })
            #expect(today != bare, "the wash is drawn")
            #expect(card == today)
            // A module keeps its own strength.
            #expect(try pixels(box { $0.notchCard(in: shape, fill: 0.14) }) == pixels(box { $0.background(NotchTokens.fill(0.14), in: shape) }))
            #expect(try pixels(box { $0.notchCard(in: shape, fill: 0.14) }) != card)
            // Whether the card is a control makes no difference to a wash.
            #expect(try pixels(box { $0.notchCard(in: shape, interactive: true) }) == today)
        }
    }

    @Test func aKeyLeftInTheDefaultsDoesNotChangeTheClassicNotchsCards() throws {
        try NotchLookState.$current.withValue(NotchLookState()) {
            let shape = Capsule()
            let today = try pixels(box { $0.background(NotchTokens.fill(0.08), in: shape) })
            let everything = NotchGlassSwitches(variant: .clear, panel: .tiles, dim: 0.4, scheme: .dark, sample: true, selected: .white)
            for surface in [NotchSurface.solid, .material] {
                let card = try pixels(box {
                    $0.notchCard(in: shape).environment(\.notchSurface, surface).environment(\.notchGlassSwitches, everything)
                        .environment(\.notchOnDesktop, true)
                })
                #expect(card == today, "\(surface)")
            }
        }
    }

    @Test func aSelectedCardOnTheClassicNotchIsTheAccentWash() throws {
        try NotchLookState.$current.withValue(NotchLookState()) {
            let shape = Capsule()
            let expected = try pixels(box { $0.background(accent.opacity(NotchTokens.selectionOpacity), in: shape) })
            #expect(try pixels(box { $0.notchCard(in: shape, selected: true).environment(\.notchAccent, accent) }) == expected)
        }
    }

    // MARK: the dimming layer

    func tone(_ backdrop: NotchBackdrop) throws -> Double {
        let renderer = ImageRenderer(content: ZStack { Color.white; backdrop }.frame(width: 20, height: 20))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return Double(try #require(bitmap.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB)).redComponent)
    }

    @Test func theDimIsABlackLayerOverTheGlassOnly() throws {
        let none = try tone(NotchBackdrop(surface: glass, bodyHeight: 10))
        let light = try tone(NotchBackdrop(surface: glass, bodyHeight: 10, dim: 0.15))
        let heavy = try tone(NotchBackdrop(surface: glass, bodyHeight: 10, dim: 0.4))
        #expect(none > 0.99, "no dim, no layer: what is behind shows as it is")
        #expect(light < none - 0.05)
        #expect(heavy < light - 0.05)
        #expect(try tone(NotchBackdrop(surface: glass, bodyHeight: 10, dim: 0)) == none)
        // The classic notch's black and blur do not have it.
        for surface in [NotchSurface.solid, .material] {
            #expect(try tone(NotchBackdrop(surface: surface, bodyHeight: 10, dim: 0.4)) == tone(NotchBackdrop(surface: surface, bodyHeight: 10)), "\(surface)")
        }
    }
}

// MARK: the open notch, hosted

private final class ProbeFrame {
    var value: CGRect?
    /// The colour scheme the tab's content was last drawn in.
    var scheme: ColorScheme?
    /// How many times the tab's content appeared: it must not appear again when the notch goes to a toast and back.
    var appeared = 0
}

/// A tab's content that reports where it is, which colour scheme it is drawn in and that it appeared.
private struct TabProbe: View {
    let frame: ProbeFrame
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let _ = (frame.scheme = scheme)
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
/// frame, and as many more tabs as asked for.
private struct OpenNotch {
    let hosting: NSHostingView<NotchRootView>
    let window: NSWindow
    let frame: ProbeFrame
    let geometry: NotchGeometry
    let model: NotchViewModel

    /// Builds it and lays it out. `switches` nil leaves the root view's own default, which is what the tests that build one with no
    /// switches see.
    static func make(look: NotchLook, tinted: Bool = false, tabs: Int = 1, _ switches: NotchGlassSwitches?) async throws -> OpenNotch {
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let frame = ProbeFrame()
        let modules = [ProbeModule("probe", order: 0, frame: frame)]
            + (1..<max(tabs, 1)).map { ProbeModule(ModuleID(stringLiteral: "other\($0)"), order: $0, frame: nil) }
        let harness = RegistryHarness(modules)
        await harness.registry.bootstrap()
        harness.settings.set(look, for: InterfaceSettings.look)
        harness.settings.set(tinted, for: InterfaceSettings.glassTint)
        let theme = NotchTheme(settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let model = NotchViewModel(
            scheduler: harness.scheduler, availableTabs: { [registry = harness.registry] in registry.tabs.map(\.id) }, delays: { (.zero, .zero) }
        )
        model.open(tab: "probe")
        try #require(model.displayState == .open("probe"))
        let root = switches.map {
            NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme, switches: $0)
        } ?? NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        // Light, whatever the machine is set to, so a scheme the notch forces can be told from the window's own.
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        for _ in 0..<50 where frame.value == nil {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        hosting.layoutSubtreeIfNeeded()
        return OpenNotch(hosting: hosting, window: window, frame: frame, geometry: geometry, model: model)
    }

    func close() { window.contentView = nil }

    /// Lets the run loop turn so SwiftUI applies what changed, then lays the view out.
    func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
    }

    /// The same point on the screen of `NotchGeometryTests.macBook14`, which is what the pointer tracking works in.
    func screenPoint(_ point: CGPoint) -> CGPoint {
        let panel = geometry.panelFrame(in: NotchGeometryTests.macBook14.frame)
        return CGPoint(x: panel.minX + point.x, y: panel.maxY - point.y)
    }
}

/// Where the open notch puts a tab's content, with the sample strip and the glass switches. Layout only: nothing is read from
/// pixels, and the glass is not drawn.
@Suite struct NotchSampleStripTests {
    let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())

    func tabFrame(look: NotchLook, tinted: Bool = false, tabs: Int = 1, _ switches: NotchGlassSwitches?) async throws -> CGRect {
        let notch = try await OpenNotch.make(look: look, tinted: tinted, tabs: tabs, switches)
        defer { notch.close() }
        return try #require(notch.frame.value)
    }

    @Test func theSampleStripIsAbsentByDefault() async throws {
        for look in [NotchLook.classic, .liquidGlass] {
            let byDefault = try await tabFrame(look: look, nil)
            // The tab starts right under the notch's body (no tab bar for one tab, no strip): nothing sits above it.
            #expect(abs(byDefault.minY - geometry.notchSize.height) < 0.01, "\(look): \(byDefault)")
            #expect(try await tabFrame(look: look, .default) == byDefault)
            #expect(try await tabFrame(look: look, NotchGlassSwitches(sample: false)) == byDefault)
        }
    }

    @Test func theSampleStripSitsAboveTheTabAndTakesItsRoomWithoutGrowingTheNotch() async throws {
        for look in [NotchLook.classic, .liquidGlass] {
            let without = try await tabFrame(look: look, .default)
            let with = try await tabFrame(look: look, NotchGlassSwitches(sample: true))
            #expect(abs(with.minY - (without.minY + NotchSampleStrip.slot)) < 0.01, "\(look)")
            #expect(abs(with.maxY - without.maxY) < 0.01, "the notch is the size it was: the tab loses what the strip takes")
            #expect(abs(with.height - (without.height - NotchSampleStrip.slot)) < 0.01)
            #expect(abs(with.minX - without.minX) < 0.01 && abs(with.width - without.width) < 0.01)
        }
        #expect(NotchSampleStrip.slot == NotchSampleStrip.height + NotchSampleStrip.bottomGap)
    }

    @Test func theSwitchesOfTheSlabDoNotMoveTheTabOnEitherLook() async throws {
        let moved = NotchGlassSwitches(variant: .clear, panel: .slab, dim: 0.4, scheme: .dark, sample: false, selected: .white)
        for look in [NotchLook.classic, .liquidGlass] {
            #expect(try await tabFrame(look: look, moved) == tabFrame(look: look, .default), "\(look)")
        }
    }

    @Test func theTilesPanelChangesNothingOnTheClassicNotch() async throws {
        let tiles = NotchGlassSwitches(variant: .clear, panel: .tiles, dim: 0.4, scheme: .dark, sample: false, selected: .white)
        for tabs in [1, 2] {
            #expect(try await tabFrame(look: .classic, tabs: tabs, tiles) == tabFrame(look: .classic, tabs: tabs, .default), "\(tabs) tabs")
        }
    }
}

/// The tiles: where the open notch puts its tab bar and content when its panel has no glass of its own.
@Suite struct NotchTilesLayoutTests {
    let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let tiles = NotchGlassSwitches(panel: .tiles)

    func tabFrame(_ switches: NotchGlassSwitches?, tabs: Int, look: NotchLook = .liquidGlass) async throws -> CGRect {
        let notch = try await OpenNotch.make(look: look, tabs: tabs, switches)
        defer { notch.close() }
        return try #require(notch.frame.value)
    }

    @Test func theContentSitsInATileInsetByTheTabBarsCapsuleTheGapAndThePadding() async throws {
        let gap = NotchGlassPlan.tileGap, pad = NotchGlassPlan.tilePadding
        let capsule = 24 + 2 * NotchGlassPlan.tabBarInset.height
        let slab = try await tabFrame(nil, tabs: 2)
        let tiled = try await tabFrame(tiles, tabs: 2)
        // The slab: the tab bar's 24 pt and 6 below it, then the tab. Tiles: the capsule, the gap, then the tile's padding.
        #expect(abs(slab.minY - (geometry.notchSize.height + 24 + 6)) < 0.01, "\(slab)")
        #expect(abs(tiled.minY - (geometry.notchSize.height + capsule + gap + pad)) < 0.01, "\(tiled)")
        #expect(abs(tiled.minX - (slab.minX + pad)) < 0.01 && abs(tiled.width - (slab.width - 2 * pad)) < 0.01)
        #expect(abs(tiled.maxY - (slab.maxY - pad)) < 0.01, "the notch is the size it was")
    }

    @Test func withOneTabThereIsNoCapsuleAndTheTileIsStillAroundTheContent() async throws {
        let pad = NotchGlassPlan.tilePadding
        let slab = try await tabFrame(nil, tabs: 1)
        let tiled = try await tabFrame(tiles, tabs: 1)
        #expect(abs(tiled.minY - (slab.minY + pad)) < 0.01 && abs(tiled.maxY - (slab.maxY - pad)) < 0.01)
        #expect(abs(tiled.width - (slab.width - 2 * pad)) < 0.01)
    }

    @Test func theTilesAreTheSameForEveryVariantAndNothingElseMovesThem() async throws {
        let reference = try await tabFrame(tiles, tabs: 2)
        for switches in [
            NotchGlassSwitches(variant: .clear, panel: .tiles), NotchGlassSwitches(panel: .tiles, dim: 0.3),
            NotchGlassSwitches(panel: .tiles, scheme: .dark), NotchGlassSwitches(panel: .tiles, selected: .white),
        ] {
            #expect(try await tabFrame(switches, tabs: 2) == reference, "\(switches)")
        }
    }

    // MARK: the gaps are part of the notch

    /// A point in the gap between the tab bar's capsule and the content's tile, in the open notch with tiles.
    fileprivate func gapPoint(_ notch: OpenNotch) throws -> CGPoint {
        let content = try #require(notch.frame.value)
        return CGPoint(x: content.midX, y: content.minY - NotchGlassPlan.tilePadding - NotchGlassPlan.tileGap / 2)
    }

    @Test func aPointInTheGapIsInsideTheNotchForTheHoverTrackerAndTheClickOutsideCheck() async throws {
        let notch = try await OpenNotch.make(look: .liquidGlass, tabs: 2, tiles)
        defer { notch.close() }
        let gap = try gapPoint(notch)
        let screen = notch.screenPoint(gap)
        // The pointer tracking works on the notch's rect, not on what is drawn, so the gap is inside it: hover keeps the notch open
        // and a press there is not a click outside.
        let state = notch.model.displayState
        #expect(state == .open("probe"))
        #expect(
            notch.geometry.pointerZone(at: screen, state: state, contentHeight: NotchTab.defaultHeight, in: NotchGeometryTests.macBook14.frame)
                == .notch
        )
        #expect(
            notch.geometry.pointerZone(at: CGPoint(x: screen.x, y: screen.y), state: state, contentHeight: 190, in: NotchGeometryTests.macBook14.frame)
                == .notch
        )
        // And a point beside the notch is outside, so the test can tell.
        let beside = CGPoint(x: 5, y: gap.y)
        #expect(
            notch.geometry.pointerZone(at: notch.screenPoint(beside), state: state, contentHeight: 190, in: NotchGeometryTests.macBook14.frame)
                == .outside
        )
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
        let notch = try await OpenNotch.make(look: .liquidGlass, tabs: 2, tiles)
        defer { notch.close() }
        let gap = try gapPoint(notch)
        let inGap = try alpha(notch, at: gap)
        // (That it is too faint to see is the plan's test: `hitOpacity` is under three levels of 255.)
        #expect(inGap > 0, "the veil is there, in the gap too: \(inGap)")
        #expect(try alpha(notch, at: CGPoint(x: 5, y: gap.y)) == 0, "outside the notch's shape the panel is transparent, which is what the test can tell")
    }

    @Test func theGapsOfTheClassicNotchAreBlackWhateverKeyIsSet() async throws {
        let classic = try await OpenNotch.make(look: .classic, tabs: 2, tiles)
        defer { classic.close() }
        #expect(try alpha(classic, at: gapPoint(classic)) > 0.99)
    }

    // MARK: the views keep their identity

    @Test func theTabIsNotRebuiltWhenTheNotchGoesToAToastAndBackWithTilesOrWithTheSlab() async throws {
        for switches in [NotchGlassSwitches(panel: .slab), tiles] {
            let notch = try await OpenNotch.make(look: .liquidGlass, tabs: 2, switches)
            defer { notch.close() }
            #expect(notch.frame.appeared == 1, "\(switches.panel): it appeared once")
            // The toast covers the tab, which stays alive under it, hidden; the notch's glass comes back for it and goes again.
            notch.model.showToast(AnyView(Color.clear), duration: .seconds(60))
            try await notch.settle()
            #expect(notch.model.displayState == .toast)
            notch.model.open(tab: "probe")
            try await notch.settle()
            #expect(notch.model.displayState == .open("probe"))
            #expect(notch.frame.appeared == 1, "\(switches.panel): the toast and back did not rebuild the tab (\(notch.frame.appeared))")
        }
    }
}

/// `debug.glass.scheme`: the content of the notch is dark on glass when asked, and only the content.
@Suite struct NotchContentSchemeTests {
    func scheme(look: NotchLook, _ switches: NotchGlassSwitches?) async throws -> ColorScheme? {
        let notch = try await OpenNotch.make(look: look, switches)
        defer { notch.close() }
        return notch.frame.scheme
    }

    @Test func theContentKeepsTheWindowsSchemeByDefaultAndIsDarkWhenAskedOnGlass() async throws {
        #expect(try await scheme(look: .liquidGlass, nil) == .light)
        #expect(try await scheme(look: .liquidGlass, NotchGlassSwitches(scheme: .system)) == .light)
        #expect(try await scheme(look: .liquidGlass, NotchGlassSwitches(scheme: .dark)) == .dark)
        #expect(try await scheme(look: .liquidGlass, NotchGlassSwitches(variant: .clear, panel: .tiles, scheme: .dark)) == .dark)
    }

    @Test func theClassicNotchsContentIsNotForcedWhateverTheSwitchSays() async throws {
        let byDefault = try await scheme(look: .classic, nil)
        #expect(try await scheme(look: .classic, NotchGlassSwitches(scheme: .dark)) == byDefault)
    }
}

/// The selected tab with `debug.glass.selected=white`: a solid white tile, which no window server draws, so it can be read offscreen
/// (the tinted glass chip cannot), with a dark glyph. Everything else about the tab bar is as it was.
@Suite struct NotchTabSelectionTests {
    let tabs = [
        NotchTab(id: "a", title: "A", systemImage: "circle.fill", content: AnyView(EmptyView())),
        NotchTab(id: "b", title: "B", systemImage: "square.fill", content: AnyView(EmptyView())),
    ]

    /// Near-white and near-black pixels in the left half (the first tab, not selected) and the right half (the second tab, which is).
    func counts(surface: NotchSurface, switches: NotchGlassSwitches?) throws -> (whiteLeft: Int, whiteRight: Int, darkRight: Int) {
        var bar: AnyView = AnyView(TabBar(tabs: tabs, selected: "b") { _ in }.environment(\.notchSurface, surface))
        if let switches { bar = AnyView(bar.environment(\.notchGlassSwitches, switches)) }
        let renderer = ImageRenderer(content: ZStack { Color(white: 0.3); bar.environment(\.colorScheme, .dark) }.frame(width: 72, height: 24))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var result = (whiteLeft: 0, whiteRight: 0, darkRight: 0)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let level = Double(color.redComponent)
                if x < bitmap.pixelsWide / 2 {
                    if level > 0.95 { result.whiteLeft += 1 }
                } else {
                    if level > 0.95 { result.whiteRight += 1 }
                    if level < 0.1 { result.darkRight += 1 }
                }
            }
        }
        return result
    }

    @Test func withAWhiteSelectionTheSelectedTabIsAWhiteTileWithADarkGlyphOnEitherPanel() throws {
        for panel in NotchGlassPanel.allCases {
            let white = try counts(surface: .liquidGlass(tinted: false), switches: NotchGlassSwitches(panel: panel, selected: .white))
            #expect(white.whiteRight > 300, "a white capsule on the \(panel): \(white)")
            #expect(white.darkRight > 20, "with a dark glyph on it: \(white)")
            #expect(white.whiteLeft == 0, "the tab that is not selected has no tile: \(white)")
        }
    }

    @Test func otherwiseTheTabBarDrawsNoWhiteTileNorADarkGlyph() throws {
        for (surface, switches) in [
            (NotchSurface.liquidGlass(tinted: false), NotchGlassSwitches?.none),
            (.liquidGlass(tinted: false), .some(NotchGlassSwitches(panel: .tiles, selected: .tint))),
            (.solid, .some(NotchGlassSwitches(panel: .tiles, selected: .white))),
            (.material, .some(NotchGlassSwitches(panel: .tiles, selected: .white))),
        ] {
            let counted = try counts(surface: surface, switches: switches)
            // The classic notch's selected glyph is itself white (about 130 pixels); a tile is more than twice that.
            #expect(counted.whiteLeft == 0 && counted.whiteRight < 200 && counted.darkRight == 0, "\(surface) \(String(describing: switches)): \(counted)")
        }
    }
}
