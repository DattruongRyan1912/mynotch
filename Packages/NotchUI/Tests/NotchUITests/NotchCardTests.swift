import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The card modifier (`notchCard`), the sample strip and the dimming layer of U3c. What a card is made of is a value
/// (`NotchCardPlan`); the classic wash is compared pixel for pixel with the expression it replaces, on views with no glass in
/// them (glass is not drawn offscreen, and a render of it is not stable); where the sample strip is comes from layout.
@Suite struct NotchCardTests {
    let accent = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.9)
    let glass = NotchSurface.liquidGlass(tinted: false)

    func resolve(
        _ surface: NotchSurface, _ switches: NotchGlassSwitches, fill: Double = 0.08, selected: Bool = false, interactive: Bool = false
    ) -> NotchCardPlan {
        NotchCardPlan.resolve(surface: surface, switches: switches, accent: accent, fill: fill, selected: selected, interactive: interactive)
    }

    /// Every combination of the switches, for the tests that say "whatever they are".
    var everySwitch: [NotchGlassSwitches] {
        var all: [NotchGlassSwitches] = []
        for variant in NotchGlassVariant.allCases {
            for host in NotchGlassHost.allCases {
                for scheme in NotchGlassScheme.allCases {
                    for cards in NotchGlassCards.allCases {
                        for selected in NotchGlassSelected.allCases {
                            for sample in [false, true] {
                                all.append(
                                    NotchGlassSwitches(
                                        variant: variant, host: host, dim: 0.3, scheme: scheme, sample: sample, cards: cards, selected: selected
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }
        return all
    }

    // MARK: what a card is made of

    @Test func onTheClassicNotchACardIsTheWashWhateverTheSwitchesSay() {
        for surface in [NotchSurface.solid, .material] {
            for switches in everySwitch {
                #expect(resolve(surface, switches) == NotchCardPlan(fill: .wash(0.08)))
                #expect(resolve(surface, switches, fill: 0.14, interactive: true) == NotchCardPlan(fill: .wash(0.14)))
                #expect(resolve(surface, switches, selected: true) == NotchCardPlan(fill: .selectedWash(rim: false)))
            }
        }
    }

    @Test func onGlassWithFillCardsACardIsTheWashAndASelectedOneIsTheCapsuleWithItsRim() {
        for switches in everySwitch where switches.cards == .fill {
            #expect(resolve(glass, switches) == NotchCardPlan(fill: .wash(0.08)))
            #expect(resolve(glass, switches, fill: 0.05) == NotchCardPlan(fill: .wash(0.05)))
            #expect(resolve(glass, switches, selected: true) == NotchCardPlan(fill: .selectedWash(rim: true)))
        }
    }

    @Test func onGlassWithGlassCardsACardIsGlassOfTheNotchsVariant() {
        let regular = NotchGlassSwitches(variant: .regular, cards: .glass)
        let clear = NotchGlassSwitches(variant: .clear, cards: .glass)
        #expect(resolve(glass, regular) == NotchCardPlan(fill: .glass(Glass.regular)))
        #expect(resolve(glass, clear) == NotchCardPlan(fill: .glass(Glass.clear)))
        #expect(resolve(glass, clear) != NotchCardPlan(fill: .glass(Glass.regular)))
        // Whatever tint the notch has, a plain card has none of its own.
        #expect(resolve(.liquidGlass(tinted: true), clear) == NotchCardPlan(fill: .glass(Glass.clear)))
    }

    @Test func aGlassCardThatIsAControlIsInteractive() {
        let clear = NotchGlassSwitches(variant: .clear, cards: .glass)
        #expect(resolve(glass, clear, interactive: true) == NotchCardPlan(fill: .glass(Glass.clear.interactive())))
        #expect(resolve(glass, clear, interactive: true) != resolve(glass, clear))
        #expect(resolve(glass, NotchGlassSwitches(cards: .glass), interactive: true) == NotchCardPlan(fill: .glass(Glass.regular.interactive())))
    }

    @Test func aSelectedCardIsGlassTintedWithTheAccentOrAWhiteTileWithADarkGlyph() {
        let tint = accent.opacity(NotchCardPlan.selectedTintOpacity)
        for variant in NotchGlassVariant.allCases {
            let tinted = NotchGlassSwitches(variant: variant, cards: .glass, selected: .tint)
            #expect(resolve(glass, tinted, selected: true) == NotchCardPlan(fill: .glass(variant.glass.tint(tint))))
            #expect(resolve(glass, tinted, selected: true, interactive: true) == NotchCardPlan(fill: .glass(variant.glass.tint(tint).interactive())))

            let white = NotchGlassSwitches(variant: variant, cards: .glass, selected: .white)
            #expect(resolve(glass, white, selected: true) == NotchCardPlan(fill: .onTile))
            #expect(resolve(glass, white, selected: true, interactive: true) == NotchCardPlan(fill: .onTile))
            // The switch is only for what is selected.
            #expect(resolve(glass, white) == NotchCardPlan(fill: .glass(variant.glass)))
        }
        #expect(NotchCardPlan.selectedTintOpacity > NotchTokens.glassTintOpacity, "it marks a state, so it is stronger than the notch's hint")
        #expect(NotchCardPlan.selectedTintOpacity < 1)
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
            let everything = NotchGlassSwitches(variant: .clear, host: .appkit, dim: 0.4, scheme: .dark, sample: true, cards: .glass, selected: .white)
            for surface in [NotchSurface.solid, .material] {
                let card = try pixels(box { $0.notchCard(in: shape).environment(\.notchSurface, surface).environment(\.notchGlassSwitches, everything) })
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

// MARK: the sample strip

private final class ProbeModule: FeatureModule {
    let descriptor = ModuleDescriptor(id: "probe", displayName: "Probe", systemImage: "circle", defaultEnabled: true, order: 0)
    let frame: ProbeFrame
    init(_ frame: ProbeFrame) { self.frame = frame }
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? {
        NotchTab(id: "probe", title: "Probe", systemImage: "circle", preferredHeight: 190, content: AnyView(TabProbe(frame: frame)))
    }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

private final class ProbeFrame {
    var value: CGRect?
    /// The colour scheme the tab's content was last drawn in.
    var scheme: ColorScheme?
}

/// A tab's content that reports where it is and which colour scheme it is drawn in.
private struct TabProbe: View {
    let frame: ProbeFrame
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let _ = (frame.scheme = scheme)
        Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [frame] in frame.value = $0 }
    }
}

/// An open notch of the real root view hosted in a window that is never shown, with a tab whose content reports its frame.
private struct OpenNotch {
    let hosting: NSHostingView<NotchRootView>
    let window: NSWindow
    let frame: ProbeFrame
    let geometry: NotchGeometry

    /// Builds it and lays it out. `switches` nil leaves the root view's own default, which is what the tests that build one with no
    /// switches see.
    static func make(look: NotchLook, tinted: Bool = false, _ switches: NotchGlassSwitches?) async throws -> OpenNotch {
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let frame = ProbeFrame()
        let harness = RegistryHarness([ProbeModule(frame)])
        await harness.registry.bootstrap()
        harness.settings.set(look, for: InterfaceSettings.look)
        harness.settings.set(tinted, for: InterfaceSettings.glassTint)
        let theme = NotchTheme(settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [registry = harness.registry] in registry.tabs.map(\.id) }, delays: { (.zero, .zero) })
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
        return OpenNotch(hosting: hosting, window: window, frame: frame, geometry: geometry)
    }

    /// Every `NotchGlassEffectView` under the root view.
    var glassViews: [NotchGlassEffectView] {
        func collect(_ view: NSView) -> [NotchGlassEffectView] {
            (view as? NotchGlassEffectView).map { [$0] } ?? view.subviews.flatMap(collect)
        }
        return collect(hosting)
    }

    func close() { window.contentView = nil }
}

/// Where the open notch puts a tab's content, with the sample strip and the glass switches. Layout only: nothing is read from
/// pixels, and the glass is not drawn.
@Suite struct NotchSampleStripTests {
    let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())

    func tabFrame(look: NotchLook, tinted: Bool = false, _ switches: NotchGlassSwitches?) async throws -> CGRect {
        let notch = try await OpenNotch.make(look: look, tinted: tinted, switches)
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

    @Test func theOtherSwitchesDoNotMoveTheTabOnEitherLook() async throws {
        let moved = NotchGlassSwitches(variant: .clear, host: .appkit, dim: 0.4, scheme: .dark, sample: false, cards: .glass, selected: .white)
        for look in [NotchLook.classic, .liquidGlass] {
            #expect(try await tabFrame(look: look, moved) == tabFrame(look: look, .default), "\(look)")
        }
    }

    @Test func theInnerContainerAndTheAppKitHostDoNotMoveOrResizeTheTabEither() async throws {
        let plain = try await tabFrame(look: .liquidGlass, NotchGlassSwitches(sample: true))
        #expect(try await tabFrame(look: .liquidGlass, NotchGlassSwitches(sample: true, cards: .glass)) == plain, "inner container")
        #expect(try await tabFrame(look: .liquidGlass, NotchGlassSwitches(host: .appkit, sample: true)) == plain, "AppKit host")
        #expect(try await tabFrame(look: .liquidGlass, NotchGlassSwitches(variant: .clear, host: .appkit, dim: 0.2, scheme: .dark, sample: true, cards: .glass, selected: .white)) == plain)
    }
}

/// The AppKit host: an `NSGlassEffectView` behind the SwiftUI content, which is ours (`NotchGlassEffectView`), so its place and
/// settings can be read from the view hierarchy without drawing anything.
@Suite struct NotchAppKitGlassTests {
    fileprivate func glassViews(look: NotchLook = .liquidGlass, tinted: Bool = false, _ switches: NotchGlassSwitches?) async throws -> ([NotchGlassEffectView], OpenNotch) {
        let notch = try await OpenNotch.make(look: look, tinted: tinted, switches)
        return (notch.glassViews, notch)
    }

    @Test func theAppKitHostPutsOneGlassViewBehindTheOpenNotchWithTheVariantAndTheBottomRadius() async throws {
        for (variant, style) in [(NotchGlassVariant.regular, NSGlassEffectView.Style.regular), (.clear, .clear)] {
            let (views, notch) = try await glassViews(NotchGlassSwitches(variant: variant, host: .appkit))
            defer { notch.close() }
            let view = try #require(views.first)
            #expect(views.count == 1)
            #expect(view.style == style, "\(variant)")
            #expect(view.cornerRadius == 24, "the open notch's bottom radius")
            #expect(view.tintColor == nil)
            #expect(view.contentView != nil)
            #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil, "every click goes through to the notch")
        }
    }

    @Test func itIsInsetByTheEarsAndRunsUpPastThePanelsTopByTheBottomRadiusAndHasTheNotchsSize() async throws {
        let (views, notch) = try await glassViews(NotchGlassSwitches(host: .appkit))
        defer { notch.close() }
        let view = try #require(views.first)
        let size = notch.geometry.shapeSize(for: .open("probe"), contentHeight: 190)
        let radii = notch.geometry.cornerRadii(for: .open("probe"))
        let frame = view.convert(view.bounds, to: notch.hosting)
        #expect(abs(frame.midX - notch.geometry.panelSize.width / 2) < 0.5, "centred on the notch: \(frame)")
        #expect(abs(frame.width - (size.width - 2 * radii.top)) < 0.5, "the body, without the ears: \(frame)")
        #expect(abs(frame.height - (size.height + radii.bottom)) < 0.5, "from above the panel to the notch's bottom: \(frame)")
        let spans = [frame.minY, frame.maxY].sorted()
        #expect(abs(spans[0] + radii.bottom) < 0.5 && abs(spans[1] - size.height) < 0.5, "\(frame)")
    }

    @Test func theTintOfTheAccentGoesToTheViewOnlyWhenAsked() async throws {
        let (tinted, notchA) = try await glassViews(tinted: true, NotchGlassSwitches(host: .appkit))
        defer { notchA.close() }
        #expect(tinted.first?.tintColor != nil)
        let (plain, notchB) = try await glassViews(tinted: false, NotchGlassSwitches(host: .appkit))
        defer { notchB.close() }
        #expect(plain.first?.tintColor == nil)
    }

    @Test func noGlassViewExistsWithTheSwiftUIHostOrOnTheClassicNotchWhateverTheSwitchesSay() async throws {
        let (swiftUI, notchA) = try await glassViews(NotchGlassSwitches(variant: .clear, host: .swiftui))
        defer { notchA.close() }
        #expect(swiftUI.isEmpty)
        let (byDefault, notchB) = try await glassViews(nil)
        defer { notchB.close() }
        #expect(byDefault.isEmpty)
        let (classic, notchC) = try await glassViews(look: .classic, NotchGlassSwitches(variant: .clear, host: .appkit, dim: 0.4, scheme: .dark, sample: true, cards: .glass))
        defer { notchC.close() }
        #expect(classic.isEmpty, "a key left in the defaults does not touch the classic notch")
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
        #expect(try await scheme(look: .liquidGlass, NotchGlassSwitches(variant: .clear, host: .appkit, scheme: .dark, cards: .glass)) == .dark)
    }

    @Test func theClassicNotchsContentIsNotForcedWhateverTheSwitchSays() async throws {
        let byDefault = try await scheme(look: .classic, nil)
        #expect(try await scheme(look: .classic, NotchGlassSwitches(scheme: .dark)) == byDefault)
    }
}

/// The selected tab with `debug.glass.cards=glass`, `selected=white`: a solid white tile, which no window server draws, so it can
/// be read offscreen (the tinted glass one cannot), with a dark glyph. Everything else about the tab bar is as it was.
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

    @Test func withAWhiteSelectionTheSelectedTabIsAWhiteTileWithADarkGlyph() throws {
        let white = try counts(surface: .liquidGlass(tinted: false), switches: NotchGlassSwitches(cards: .glass, selected: .white))
        #expect(white.whiteRight > 300, "a white capsule: \(white)")
        #expect(white.darkRight > 20, "with a dark glyph on it: \(white)")
        #expect(white.whiteLeft == 0, "the tab that is not selected has no tile: \(white)")
    }

    @Test func otherwiseTheTabBarDrawsNoWhiteTileNorADarkGlyph() throws {
        for (surface, switches) in [
            (NotchSurface.liquidGlass(tinted: false), NotchGlassSwitches?.none),
            (.liquidGlass(tinted: false), .some(NotchGlassSwitches(cards: .fill, selected: .white))),
            (.solid, .some(NotchGlassSwitches(cards: .glass, selected: .white))),
            (.material, .some(NotchGlassSwitches(cards: .glass, selected: .white))),
        ] {
            let counted = try counts(surface: surface, switches: switches)
            // The classic notch's selected glyph is itself white (about 130 pixels); a tile is more than twice that.
            #expect(counted.whiteLeft == 0 && counted.whiteRight < 200 && counted.darkRight == 0, "\(surface) \(String(describing: switches)): \(counted)")
        }
    }
}
