import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The Liquid Glass look: which glass each part of the notch asks for, that the notch, its open state and its bubbles are one
/// glass family with stable identities, what the notch's own views are drawn with on glass, and that the glass path builds and
/// lays out like the classic one. Glass is composited by the window server, so an offscreen render shows what SwiftUI itself
/// draws (the content on top, and nothing where the glass is); the look of the glass is for the eye.
@Suite struct LiquidGlassTests {
    typealias RGB = NotchAccent.RGB

    let harness = RegistryHarness([])
    let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let accent = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.9)

    // MARK: identities of the glass family

    @Test func theNotchHasOneGlassIdentityInEveryStateSoOpeningAndClosingMorphsOneShape() {
        let states: [NotchState] = [.closed, .compact, .open(nil), .open("a"), .open("b"), .toast]
        #expect(Set(states.map(NotchGlassID.notch(in:))) == [.notch])
    }

    @Test func aBubbleIsNamedAfterItsActivityAndIsNeverTheNotch() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        for index in 1...4 {
            center.set(
                LiveActivity(id: "a\(index)", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "Hoạt động \(index)"),
                from: "m"
            )
        }
        let slots = ActivitySlot.bubbles(of: center, capacity: 3)
        let ids = slots.map(NotchGlassID.init(slot:))
        #expect(Set(ids).count == ids.count, "no two bubbles share an identity")
        #expect(!ids.contains(.notch))
        // The same slots again, and in another order, give the same names: a bubble that moves keeps its glass.
        #expect(slots.reversed().map(NotchGlassID.init(slot:)) == ids.reversed())
        #expect(ActivitySlot.bubbles(of: center, capacity: 3).map(NotchGlassID.init(slot:)) == ids)
    }

    @Test func thePlusNBubbleKeepsItsIdentityWhileItsNumberChanges() {
        #expect(NotchGlassID(slot: .overflow(3)) == NotchGlassID(slot: .overflow(4)))
        #expect(NotchGlassID(slot: .overflow(3)) != .notch)
    }

    @Test func onlyTheOpenNotchIsInteractiveGlass() {
        #expect(NotchState.open(nil).wantsInteractiveGlass)
        #expect(NotchState.open("a").wantsInteractiveGlass)
        for state in [NotchState.closed, .compact, .toast] {
            #expect(!state.wantsInteractiveGlass, "\(state)")
        }
    }

    // MARK: the glass itself

    @Test func glassIsTheRegularVariantAndSolidOrMaterialAskForNone() {
        #expect(NotchSurface.liquidGlass(tinted: false).glass(accent: accent, interactive: false) == Glass.regular)
        #expect(NotchSurface.solid.glass(accent: accent, interactive: true) == nil)
        #expect(NotchSurface.material.glass(accent: accent, interactive: true) == nil)
    }

    @Test func glassIsTintedWithTheAccentAtLowStrengthOnlyWhenAsked() {
        #expect(NotchTokens.glassTintOpacity > 0 && NotchTokens.glassTintOpacity <= 0.3, "a hint of the accent, not a coat of it")
        #expect(
            NotchSurface.liquidGlass(tinted: true).glass(accent: accent, interactive: false)
                == Glass.regular.tint(accent.opacity(NotchTokens.glassTintOpacity))
        )
        #expect(NotchSurface.liquidGlass(tinted: true).glass(accent: accent, interactive: false) != Glass.regular)
        #expect(NotchSurface.liquidGlass(tinted: false).glass(accent: accent, interactive: false) == Glass.regular)
    }

    @Test func interactiveGlassIsAskedForOnlyWhenTheCallerWantsIt() {
        #expect(NotchSurface.liquidGlass(tinted: false).glass(accent: accent, interactive: true) == Glass.regular.interactive())
        #expect(NotchSurface.liquidGlass(tinted: false).glass(accent: accent, interactive: true) != Glass.regular)
        #expect(
            NotchSurface.liquidGlass(tinted: true).glass(accent: accent, interactive: true)
                == Glass.regular.tint(accent.opacity(NotchTokens.glassTintOpacity)).interactive()
        )
    }

    // MARK: legibility

    @Test func onGlassTheNotchsOwnViewsUseTheSystemsForegroundStylesAndOtherwiseTheFixedOnes() {
        #expect(NotchSurface.liquidGlass(tinted: false).foreground == .vibrant)
        #expect(NotchSurface.liquidGlass(tinted: true).foreground == .vibrant)
        #expect(NotchSurface.solid.foreground == .fixed)
        #expect(NotchSurface.material.foreground == .fixed)
    }

    @Test func glassHasTheDarkSchemeSoContentThatStillAssumesLightOnDarkStaysReadable() {
        #expect(NotchSurface.liquidGlass(tinted: false).colorScheme == .dark)
        #expect(NotchSurface.solid.colorScheme == nil)
        #expect(NotchSurface.material.colorScheme == nil)
    }

    /// The brightest-or-darkest pixel of the first tab of a tab bar drawn on mid grey (the tab is not selected, so only its
    /// icon differs from the grey): a positive number is lighter than the grey, a negative one darker.
    func iconTone(surface: NotchSurface, scheme: ColorScheme) throws -> Double {
        let tabs = [
            NotchTab(id: "a", title: "A", systemImage: "circle.fill", content: AnyView(EmptyView())),
            NotchTab(id: "b", title: "B", systemImage: "square.fill", content: AnyView(EmptyView())),
        ]
        let view = TabBar(tabs: tabs, selected: "b") { _ in }
            .environment(\.notchSurface, surface)
            .environment(\.colorScheme, scheme)
            .background(Color(.sRGB, white: 0.5))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var tone = 0.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<30 {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let difference = Double(color.redComponent) - 0.5
                if abs(difference) > abs(tone) { tone = difference }
            }
        }
        return tone
    }

    @Test func aTabIconOnGlassFollowsTheSchemeLikeAnySystemStyleWhileTheClassicOneIsFixedWhite() throws {
        let glass = NotchSurface.liquidGlass(tinted: false)
        #expect(try iconTone(surface: glass, scheme: .dark) > 0.2, "light on the dark glass")
        #expect(try iconTone(surface: glass, scheme: .light) < -0.1, "darker than the grey if the scheme were light: nothing assumes white")
        #expect(try iconTone(surface: .solid, scheme: .dark) > 0.2)
        #expect(try iconTone(surface: .solid, scheme: .light) > 0.2, "classic keeps its white whatever the scheme is")
    }

    /// WCAG relative luminance and contrast of colours in sRGB, 0...1 a channel.
    func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    @Test func theSelectedTabShowsOnGlassForEveryAccentOverTheLightestAndTheUsualGlass() {
        // Dark regular glass over a bright wallpaper reads about as light as a 35 % grey, over most things as a 20 % one. These
        // two grey levels are estimates, not measurements (nothing is captured here); the capsule has to hold on both.
        // (name, accent, lowest contrast of the capsule against the lightest glass). The ordinary accents hold 1.2 there. A custom
        // pick of black or a deep blue is lifted only as far as a black notch needs (`legibleOnBlack`), which is a dark grey or
        // blue: it still shows against the usual glass, and against the lightest only a little. That is the limit of a dark
        // accent on a mid-grey surface, and the icon's own colour still tells the selected tab from the others.
        let ordinary: [(String, RGB, Double)] = NotchAccent.Palette.allCases.map { ($0.rawValue, NotchAccent.palette($0).resolved(system: $0.rgb), 1.2) }
            + [("system", NotchAccent.system.resolved(system: RGB(red: 10, green: 132, blue: 255)), 1.2)]
        let dark: [(String, RGB, Double)] = [
            ("black", NotchAccent.custom(RGB(red: 0, green: 0, blue: 0)).resolved(system: RGB(red: 0, green: 0, blue: 0)), 1.1),
            ("deep blue", NotchAccent.custom(RGB(red: 0, green: 0, blue: 102)).resolved(system: RGB(red: 0, green: 0, blue: 0)), 1.1),
        ]
        let opacity = Double(NotchTokens.glassSelectionOpacity)
        for floor in [0.2, 0.35] {
            for (name, rgb, lightest) in ordinary + dark {
                func mixed(_ channel: UInt8) -> Double { opacity * Double(channel) / 255 + (1 - opacity) * floor }
                let capsule = luminance(mixed(rgb.red), mixed(rgb.green), mixed(rgb.blue))
                #expect(contrast(1, capsule) >= 3, "white icon on the \(name) capsule over \(floor) grey")
                let against = contrast(luminance(floor, floor, floor), capsule)
                #expect(against >= (floor == 0.35 ? lightest : 1.2), "the \(name) capsule against \(floor) grey is \(against)")
            }
        }
    }

    /// The red of the selected tab's capsule, drawn over black with a red accent: its opacity.
    func capsuleStrength(on surface: NotchSurface) throws -> Double {
        let tabs = [
            NotchTab(id: "a", title: "A", systemImage: "circle", content: AnyView(EmptyView())),
            NotchTab(id: "b", title: "B", systemImage: "square", content: AnyView(EmptyView())),
        ]
        let view = TabBar(tabs: tabs, selected: "a") { _ in }
            .environment(\.notchAccent, Color(.sRGB, red: 1, green: 0, blue: 0))
            .environment(\.notchSurface, surface)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        // Left of the icon, inside the capsule.
        return Double(try #require(bitmap.colorAt(x: 4, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)).redComponent)
    }

    @Test func theTabBarDrawsItsSelectionAtTheStrengthOfTheSurface() throws {
        // Measured through SwiftUI's own blending, so only the order and the sameness are compared, not the numbers.
        let classic = try capsuleStrength(on: .solid)
        #expect(classic > 0.2, "the capsule is drawn")
        #expect(try capsuleStrength(on: .material) == classic)
        #expect(try capsuleStrength(on: .liquidGlass(tinted: false)) > classic + 0.08, "glass takes more of the accent")
    }

    @Test func glassMarksASelectionMoreStronglyThanTheClassicNotchDoes() {
        #expect(NotchSurface.liquidGlass(tinted: false).selectionOpacity == NotchTokens.glassSelectionOpacity)
        #expect(NotchSurface.solid.selectionOpacity == NotchTokens.selectionOpacity)
        #expect(NotchSurface.material.selectionOpacity == NotchTokens.selectionOpacity)
        #expect(NotchTokens.glassSelectionOpacity > NotchTokens.selectionOpacity)
    }

    // MARK: drawn offscreen

    func theme(_ look: NotchLook, tinted: Bool = false, settings: SettingsStore? = nil) -> NotchTheme {
        let settings = settings ?? SettingsStore(defaults: makeIsolatedDefaults())
        settings.set(look, for: InterfaceSettings.look)
        settings.set(tinted, for: InterfaceSettings.glassTint)
        return NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
    }

    func makeModel() -> NotchViewModel {
        NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
    }

    func rootView(model: NotchViewModel, theme: NotchTheme?) -> NotchRootView {
        NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
    }

    func render(_ view: some View) throws -> NSBitmapImageRep {
        let size = geometry.panelSize
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    /// An activity whose leading view is a white square, so what SwiftUI draws on top of the notch can be found.
    func publishActivity(_ id: String = "a", priority: ActivityPriority = .normal) {
        harness.activities.set(
            LiveActivity(
                id: id, priority: priority, leading: AnyView(Color.white.frame(width: 10, height: 10)),
                trailing: AnyView(Color.clear), summary: id
            ),
            from: "m"
        )
    }

    /// The box around the opaque white pixels, as (minX, minY, maxX, maxY); nil when there are none.
    func whiteBox(_ bitmap: NSBitmapImageRep) -> [Int]? {
        var box: [Int]?
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent == 1,
                      color.redComponent > 0.95, color.greenComponent > 0.95, color.blueComponent > 0.95 else { continue }
                box = box.map { [min($0[0], x), min($0[1], y), max($0[2], x), max($0[3], y)] } ?? [x, y, x, y]
            }
        }
        return box
    }

    func pillPoint() -> CGPoint {
        CGPoint(x: geometry.panelSize.width / 2 + geometry.centerOffset, y: geometry.notchSize.height - 6)
    }

    @Test func theCollapsedNotchIsBlackInTheClassicLookAndGlassInTheOther() throws {
        publishActivity()
        let model = makeModel()
        model.hasActivity = true
        let classic = try render(rootView(model: model, theme: theme(.classic)))
        let point = pillPoint()
        let black = try #require(classic.colorAt(x: Int(point.x), y: Int(point.y)))
        #expect(black.alphaComponent == 1 && black.redComponent == 0 && black.greenComponent == 0 && black.blueComponent == 0)

        let glass = try render(rootView(model: model, theme: theme(.liquidGlass)))
        let seen = try #require(glass.colorAt(x: Int(point.x), y: Int(point.y)))
        // Not the black SwiftUI fills the classic notch with: the glass is made by the window server. (Offscreen, the renderer
        // shows what it cannot draw as transparent, or as a flat placeholder when the view also takes drops.)
        #expect(!(seen.alphaComponent == 1 && seen.redComponent == 0 && seen.greenComponent == 0 && seen.blueComponent == 0))
    }

    @Test func theGlassPathDrawsTheContentWhereTheClassicPathDoes() throws {
        publishActivity()
        let model = makeModel()
        model.hasActivity = true
        let classic = try #require(whiteBox(try render(rootView(model: model, theme: theme(.classic)))))
        let glass = try #require(whiteBox(try render(rootView(model: model, theme: theme(.liquidGlass)))))
        #expect(glass == classic)
        let tinted = try #require(whiteBox(try render(rootView(model: model, theme: theme(.liquidGlass, tinted: true)))))
        #expect(tinted == classic)
    }

    @Test func everyStateBuildsOnGlassAndLaysItsContentOutLikeTheClassicLook() throws {
        publishActivity("a")
        publishActivity("b", priority: .low)
        publishActivity("c", priority: .low)
        let states: [(String, (NotchViewModel) -> Void)] = [
            ("collapsed", { $0.hasActivity = true; $0.bubbleCount = 2 }),
            ("open", { $0.open(tab: nil) }),
            ("toast", { $0.showToast(AnyView(Color.white.frame(width: 20, height: 20)), duration: .seconds(60)) }),
            ("list", { $0.hasActivity = true; $0.bubbleCount = 2; $0.showList() }),
        ]
        for (name, apply) in states {
            func box(_ look: NotchLook) throws -> [Int]? {
                let model = makeModel()
                apply(model)
                return whiteBox(try render(rootView(model: model, theme: theme(look))))
            }
            #expect(try box(.liquidGlass) == box(.classic), "\(name)")
        }
    }

    // MARK: the glass layers SwiftUI builds

    func layers(named name: String, in layer: CALayer) -> Int {
        ("\(type(of: layer))" == name ? 1 : 0) + (layer.sublayers ?? []).reduce(0) { $0 + layers(named: name, in: $1) }
    }

    /// The backdrops and the glass shapes in a window that is never shown. A glass effect is made of a backdrop layer that the
    /// window server fills in, with one shape element for each glass; glasses in one `GlassEffectContainer` share a backdrop.
    func glass(of hosting: NSHostingView<NotchRootView>, in window: NSWindow) -> (backdrops: Int, shapes: Int) {
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()
        let root = hosting.layer ?? CALayer()
        return (layers(named: "CABackdropLayer", in: root), layers(named: "CASDFElementLayer", in: root))
    }

    func hostedGlass(theme: NotchTheme, activities: Int = 1, prepare: (NotchViewModel) -> Void = { _ in }) -> (backdrops: Int, shapes: Int) {
        for index in 0..<activities { publishActivity("a\(index)", priority: index == 0 ? .normal : .low) }
        let model = makeModel()
        prepare(model)
        let hosting = NSHostingView(rootView: rootView(model: model, theme: theme))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        defer { window.contentView = nil }
        return glass(of: hosting, in: window)
    }

    @Test func theClassicLookBuildsNoGlassAtAll() {
        for state in [{ (_: NotchViewModel) in }, { $0.open(tab: nil) }] {
            let found = hostedGlass(theme: theme(.classic), activities: 3) { model in
                model.hasActivity = true
                model.bubbleCount = 2
                state(model)
            }
            #expect(found.backdrops == 0 && found.shapes == 0)
        }
    }

    @Test func theNotchIsOneGlassShapeInEveryStateAndInTheOpenOne() {
        #expect(hostedGlass(theme: theme(.liquidGlass), activities: 1) { _ in } == (1, 1), "closed")
        #expect(hostedGlass(theme: theme(.liquidGlass), activities: 1) { $0.hasActivity = true } == (1, 1), "collapsed")
        #expect(hostedGlass(theme: theme(.liquidGlass), activities: 1) { $0.open(tab: nil) } == (1, 1), "open")
        #expect(hostedGlass(theme: theme(.liquidGlass), activities: 1) { $0.showToast(AnyView(EmptyView()), duration: .seconds(60)) } == (1, 1), "toast")
    }

    @Test func eachBubbleIsAGlassShapeInTheSameContainerAsTheNotch() {
        for bubbles in 1...3 {
            let found = hostedGlass(theme: theme(.liquidGlass), activities: bubbles + 1) {
                $0.hasActivity = true
                $0.bubbleCount = bubbles
            }
            // One backdrop for the whole family: a container per shape would not let them blend.
            #expect(found.backdrops == 1, "\(bubbles) bubbles")
            #expect(found.shapes == 1 + min(bubbles, geometry.bubbleCapacity), "\(bubbles) bubbles")
        }
    }

    @Test func aTintedGlassIsStillOneFamilyInOneContainer() {
        let plain = hostedGlass(theme: theme(.liquidGlass), activities: 2) { $0.hasActivity = true; $0.bubbleCount = 1 }
        let tinted = hostedGlass(theme: theme(.liquidGlass, tinted: true), activities: 2) { $0.hasActivity = true; $0.bubbleCount = 1 }
        #expect(tinted.backdrops == 1)
        #expect(tinted.shapes >= plain.shapes, "the tint adds to the glass, it does not replace a shape")
    }

    @Test func openingAndClosingTheNotchKeepsItsOneGlassShape() {
        publishActivity()
        let model = makeModel()
        model.hasActivity = true
        let hosting = NSHostingView(rootView: rootView(model: model, theme: theme(.liquidGlass)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        defer { window.contentView = nil }
        #expect(glass(of: hosting, in: window) == (1, 1))
        model.open(tab: nil)
        #expect(glass(of: hosting, in: window) == (1, 1))
        model.close()
        #expect(glass(of: hosting, in: window) == (1, 1))
    }

    @Test func theThemeCanBeMissingAndTheNotchIsClassic() throws {
        let model = makeModel()
        let view = try render(rootView(model: model, theme: nil))
        #expect(view.pixelsWide == Int(geometry.panelSize.width))
    }

    #if DEBUG
    @Test func anIdleGlassNotchNeverLaysTheHostingViewOutAgain() {
        publishActivity()
        let model = makeModel()
        model.hasActivity = true
        let hosting = FirstMouseHostingView(rootView: rootView(model: model, theme: theme(.liquidGlass, tinted: true)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let settled = hosting.layoutPasses
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        #expect(hosting.layoutPasses == settled)
        #expect(!hosting.needsLayout)
        window.contentView = nil
    }
    #endif

    // MARK: still the notch's own plumbing

    /// What a view of the notch read from its environment, each time it was drawn.
    final class Seen {
        var values: [Bool] = []
    }

    struct OnScreenProbe: View {
        let seen: Seen
        @Environment(\.notchIsOnScreen) private var onScreen
        var body: some View {
            seen.values.append(onScreen)
            return Color.clear.frame(width: 10, height: 10)
        }
    }

    @Test func theOnScreenStateStillReachesTheContentUnderGlassSoOffScreenPausingKeepsWorking() {
        let seen = Seen()
        let model = makeModel()
        model.showToast(AnyView(OnScreenProbe(seen: seen)), duration: .seconds(60))
        let hosting = NSHostingView(rootView: rootView(model: model, theme: theme(.liquidGlass)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        #expect(seen.values.last == true)
        model.isOnScreen = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()
        #expect(seen.values.last == false)
        window.contentView = nil
    }

    /// The scheme a toast's content reads in a root view hosted in a window of the light appearance.
    func schemeOfContent(look: NotchLook) -> Bool? {
        struct Probe: View {
            let seen: Seen
            @Environment(\.colorScheme) private var scheme
            var body: some View {
                seen.values.append(scheme == .dark)
                return Color.clear.frame(width: 10, height: 10)
            }
        }
        let seen = Seen()
        let model = makeModel()
        model.showToast(AnyView(Probe(seen: seen)), duration: .seconds(60))
        let hosting = NSHostingView(rootView: rootView(model: model, theme: theme(look)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.contentView = nil
        return seen.values.last
    }

    @Test func contentOnGlassIsDarkEvenInALightWindowAndClassicContentIsLeftAsItIs() {
        #expect(schemeOfContent(look: .liquidGlass) == true)
        #expect(schemeOfContent(look: .classic) == false)
    }

    func makeController(theme: NotchTheme?, captureHiding: CaptureHiding = .never) -> NotchWindowController {
        NotchWindowController(
            displayID: 1, screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities,
            delays: { (.milliseconds(150), .milliseconds(300)) },
            captureHiding: { captureHiding },
            swipesBetweenTabs: { true },
            theme: theme
        )
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func theGlassPanelIsDarkSoAppKitControlsAndTheGlassAgreeWithTheContentAndClassicIsLeftAlone() async {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let controller = makeController(theme: theme(.classic, settings: settings))
        defer { controller.close() }
        #expect(controller.appearance == nil)
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        #expect(await eventually { controller.appearance?.name == .darkAqua })
        settings.set(.classic, for: InterfaceSettings.look)
        #expect(await eventually { controller.appearance == nil })
    }

    @Test func aPanelThatStartsOnGlassIsDarkFromTheFirstFrame() {
        let controller = makeController(theme: theme(.liquidGlass))
        defer { controller.close() }
        #expect(controller.appearance?.name == .darkAqua)
    }

    @Test func hidingFromCaptureStillAppliesOnGlass() {
        let controller = makeController(theme: theme(.liquidGlass), captureHiding: .always)
        defer { controller.close() }
        #expect(controller.sharingType == .none)
        let visible = makeController(theme: theme(.liquidGlass), captureHiding: .never)
        defer { visible.close() }
        #expect(visible.sharingType == .readOnly)
    }

    // MARK: the surface for views that are not the notch

    struct SchemeProbe: View {
        let seen: Seen
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            seen.values.append(scheme == .dark)
            return Color.clear.frame(width: 10, height: 10)
        }
    }

    func draw(_ surface: NotchSurface, seen: Seen = Seen()) throws -> NSBitmapImageRep {
        let view = ZStack {
            Color.clear.frame(width: 60, height: 40).overlay { SchemeProbe(seen: seen) }.notchSurface(in: RoundedRectangle(cornerRadius: 8))
            Color.white.frame(width: 6, height: 6)
        }
        .environment(\.notchSurface, surface)
        .environment(\.colorScheme, .light)
        .frame(width: 80, height: 60)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    @Test func theSurfaceModifierFillsWithBlackInTheClassicLookAndLeavesRoomForGlassInTheOther() throws {
        // The 60 x 40 box sits at (10, 10) in the 80 x 60 image: (20, 20) is inside its rounded corner, (11, 11) outside it.
        let classic = try draw(.solid)
        let inside = try #require(classic.colorAt(x: 20, y: 20))
        #expect(inside.alphaComponent == 1 && inside.redComponent == 0)
        #expect(try #require(classic.colorAt(x: 11, y: 11)).alphaComponent == 0, "inside its shape only")

        let glass = try draw(.liquidGlass(tinted: false))
        #expect(try #require(glass.colorAt(x: 20, y: 20)).alphaComponent == 0, "no black: the glass is the window server's")
        #expect(try #require(glass.colorAt(x: 40, y: 30)).alphaComponent == 1, "what is drawn on it is still drawn")
    }

    @Test func theSurfaceModifierGivesGlassContentTheDarkSchemeAndLeavesTheClassicOneAsItIs() throws {
        let classic = Seen()
        _ = try draw(.solid, seen: classic)
        #expect(classic.values.last == false, "the light scheme of the window is kept")
        let glass = Seen()
        _ = try draw(.liquidGlass(tinted: false), seen: glass)
        #expect(glass.values.last == true)
    }
}
