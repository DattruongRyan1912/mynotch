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

    /// A value read from an offscreen render, once two renders in a row agree. ImageRenderer draws a view with no window-server
    /// part deterministically, so this returns at once; it only guards a render that was caught half way on a loaded machine.
    /// (A view with glass in it is not rendered for its pixels in this suite at all: the renderer draws it, and a drop target
    /// next to it, differently from one run to the next. What that part draws is read from `NotchGlassPlan` instead.)
    func settled<Value: Equatable>(_ read: () throws -> Value) rethrows -> Value {
        var previous = try read()
        for _ in 0..<4 {
            let next = try read()
            if next == previous { return next }
            previous = next
        }
        return previous
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

    /// The brightest-or-darkest pixel of the first tab of a tab bar drawn on mid grey (the tab is not selected, so only its
    /// icon differs from the grey): a positive number is lighter than the grey, a negative one darker.
    func iconTone(surface: NotchSurface, scheme: ColorScheme) throws -> Double {
        try settled { try drawIconTone(surface: surface, scheme: scheme) }
    }

    func drawIconTone(surface: NotchSurface, scheme: ColorScheme) throws -> Double {
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

    @Test func theSelectedTabShowsOnLightAndOnDarkGlassForEveryAccent() {
        // The glass is whatever the system makes of what is behind it: light over a bright wallpaper, dark over a dark one. These
        // grey levels are estimates, not measurements (nothing is captured here). The capsule is the accent at the classic
        // notch's opacity with a rim of the primary label colour (black on light glass, white on dark), and the icon is the
        // primary label colour. An accent as light as the glass (yellow on a bright wallpaper) leaves the capsule's fill nearly
        // invisible, so it is the rim that marks the selection, whatever the accent is.
        let accents: [(String, RGB)] = NotchAccent.Palette.allCases.map { ($0.rawValue, NotchAccent.palette($0).resolved(system: $0.rgb)) }
            + [
                ("system", NotchAccent.system.resolved(system: RGB(red: 10, green: 132, blue: 255))),
                ("black", NotchAccent.custom(RGB(red: 0, green: 0, blue: 0)).resolved(system: RGB(red: 0, green: 0, blue: 0))),
                ("deep blue", NotchAccent.custom(RGB(red: 0, green: 0, blue: 102)).resolved(system: RGB(red: 0, green: 0, blue: 0))),
            ]
        let label = 0.85
        let opacity = Double(NotchTokens.selectionOpacity)
        let rim = Double(NotchTokens.glassSelectionRim) * label
        // (glass grey, label colour: 0 black on light glass, 1 white on dark glass)
        for (floor, ink) in [(0.9, 0.0), (0.7, 0.0), (0.2, 1.0), (0.35, 1.0)] {
            let rimmed = rim * ink + (1 - rim) * floor
            #expect(contrast(luminance(rimmed, rimmed, rimmed), luminance(floor, floor, floor)) >= 1.5, "the rim against \(floor) grey")
            for (name, rgb) in accents {
                func mixed(_ channel: UInt8) -> Double { opacity * Double(channel) / 255 + (1 - opacity) * floor }
                let capsule = luminance(mixed(rgb.red), mixed(rgb.green), mixed(rgb.blue))
                func iconed(_ channel: UInt8) -> Double { label * ink + (1 - label) * mixed(channel) }
                let icon = luminance(iconed(rgb.red), iconed(rgb.green), iconed(rgb.blue))
                #expect(contrast(icon, capsule) >= 3, "the icon on the \(name) capsule over \(floor) grey")
            }
        }
    }

    /// The pixel of the selected tab's capsule at (x, middle), drawn over mid grey with a red accent in `scheme`: its green.
    func capsuleGreen(on surface: NotchSurface, scheme: ColorScheme, x: Int) throws -> Double {
        try settled { try drawCapsuleGreen(on: surface, scheme: scheme, x: x) }
    }

    func drawCapsuleGreen(on surface: NotchSurface, scheme: ColorScheme, x: Int) throws -> Double {
        let tabs = [
            NotchTab(id: "a", title: "A", systemImage: "circle", content: AnyView(EmptyView())),
            NotchTab(id: "b", title: "B", systemImage: "square", content: AnyView(EmptyView())),
        ]
        let view = TabBar(tabs: tabs, selected: "a") { _ in }
            .environment(\.notchAccent, Color(.sRGB, red: 1, green: 0, blue: 0))
            .environment(\.notchSurface, surface)
            .environment(\.colorScheme, scheme)
            .background(Color(.sRGB, white: 0.5))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return Double(try #require(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)).greenComponent)
    }

    @Test func onGlassTheSelectedCapsuleHasARimThatFollowsTheSchemeAndTheClassicOneHasNone() throws {
        let glass = NotchSurface.liquidGlass(tinted: false)
        // The capsule's fill is the accent alone on every surface; its leftmost pixel is the rim on glass.
        for scheme in [ColorScheme.light, .dark] {
            #expect(try capsuleGreen(on: glass, scheme: scheme, x: 4) == capsuleGreen(on: .solid, scheme: scheme, x: 4), "the fill is the same")
        }
        let classicDark = try capsuleGreen(on: .solid, scheme: .dark, x: 0)
        #expect(try capsuleGreen(on: .solid, scheme: .light, x: 0) == classicDark, "the classic capsule has no rim, in any scheme")
        #expect(try capsuleGreen(on: .material, scheme: .dark, x: 0) == classicDark)
        #expect(try capsuleGreen(on: glass, scheme: .dark, x: 0) > classicDark + 0.02, "a light rim on dark glass")
        #expect(try capsuleGreen(on: glass, scheme: .light, x: 0) < classicDark - 0.02, "a dark rim on light glass")
    }

    @Test func theRimIsAHairlineOfTheLabelColour() {
        #expect(NotchTokens.glassSelectionRim > 0 && NotchTokens.glassSelectionRim <= 0.5)
    }

    // MARK: text on glass

    /// A square drawn with `style` over mid grey in `scheme`: its pixel.
    func swatch(_ style: AnyShapeStyle, scheme: ColorScheme) throws -> NSColor {
        let colors = try settled { () -> [CGFloat] in
            let color = try drawSwatch(style, scheme: scheme)
            return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        }
        return NSColor(srgbRed: colors[0], green: colors[1], blue: colors[2], alpha: colors[3])
    }

    func drawSwatch(_ style: AnyShapeStyle, scheme: ColorScheme) throws -> NSColor {
        let view = ZStack { Color(.sRGB, white: 0.5); Rectangle().fill(style).frame(width: 8, height: 8) }
            .environment(\.colorScheme, scheme).frame(width: 12, height: 12)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return try #require(bitmap.colorAt(x: 6, y: 6)?.usingColorSpace(.sRGB))
    }

    @Test func theNotchsOwnTextOnGlassIsTheSystemsPrimaryAndSecondaryStyleNotAColourOfOurs() throws {
        let glass = NotchSurface.liquidGlass(tinted: false)
        for scheme in [ColorScheme.light, .dark] {
            #expect(try swatch(glass.primaryStyle, scheme: scheme) == swatch(AnyShapeStyle(.primary), scheme: scheme), "\(scheme)")
            #expect(try swatch(glass.secondaryStyle, scheme: scheme) == swatch(AnyShapeStyle(.secondary), scheme: scheme), "\(scheme)")
        }
        // And the classic notch's are the fixed ones, whatever the scheme.
        for scheme in [ColorScheme.light, .dark] {
            #expect(try swatch(NotchSurface.solid.primaryStyle, scheme: scheme) == swatch(AnyShapeStyle(NotchTokens.primaryText), scheme: scheme))
        }
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

    func pillPoint() -> CGPoint {
        CGPoint(x: geometry.panelSize.width / 2 + geometry.centerOffset, y: geometry.notchSize.height - 6)
    }

    /// The pill of the classic root view, which has no glass in it, so it renders the same way every time: opaque black.
    @Test func theCollapsedClassicNotchIsOpaqueBlack() throws {
        publishActivity()
        let model = makeModel()
        model.hasActivity = true
        let point = pillPoint()
        let black = try settled { () -> [CGFloat] in
            let bitmap = try render(rootView(model: model, theme: theme(.classic)))
            let color = try #require(bitmap.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.sRGB))
            return [color.alphaComponent, color.redComponent, color.greenComponent, color.blueComponent]
        }
        #expect(black[0] == 1 && black[1] < 0.01 && black[2] < 0.01 && black[3] < 0.01)
    }

    /// A smoke test, and no more: the glass root view renders in every state without an error and at the panel's size. What it
    /// draws is not read: the offscreen renderer draws a glass view, and the drop target beside it, differently from one run to
    /// the next, so a pixel here could only say which of its two moods it was in. Where the glass goes is `NotchGlassPlan`'s
    /// and `NotchGlassLayoutTests`'.
    @Test func theGlassRootViewRendersInEveryStateAtThePanelsSize() throws {
        publishActivity("a")
        publishActivity("b", priority: .low)
        publishActivity("c", priority: .low)
        let states: [(String, (NotchViewModel) -> Void)] = [
            ("closed", { _ in }),
            ("collapsed", { $0.hasActivity = true; $0.bubbleCount = 2 }),
            ("open", { $0.open(tab: nil) }),
            ("toast", { $0.showToast(AnyView(Color.white.frame(width: 20, height: 20)), duration: .seconds(60)) }),
            ("list", { $0.hasActivity = true; $0.bubbleCount = 2; $0.showList() }),
        ]
        for (name, apply) in states {
            let model = makeModel()
            apply(model)
            let bitmap = try render(rootView(model: model, theme: theme(.liquidGlass, tinted: true)))
            #expect(bitmap.pixelsWide == Int(geometry.panelSize.width) && bitmap.pixelsHigh == Int(geometry.panelSize.height), "\(name)")
        }
    }

    @Test func theThemeCanBeMissingAndTheNotchIsClassic() throws {
        let model = makeModel()
        let view = try render(rootView(model: model, theme: nil))
        #expect(view.pixelsWide == Int(geometry.panelSize.width))
    }

    /// Spins the run loop until `condition` holds, for at most `seconds`.
    func spin(until condition: () -> Bool, seconds: Double = 5) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
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
        // First until the first layout has settled: the count has stopped changing for a run of turns, however slow they are.
        var last = -1
        var quiet = 0
        spin(until: {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
            quiet = hosting.layoutPasses == last ? quiet + 1 : 0
            last = hosting.layoutPasses
            return quiet >= 10
        })
        let settled = hosting.layoutPasses
        // Then a stretch of turns in which nothing may lay it out: counted in run-loop turns, not in seconds.
        for _ in 0..<15 { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
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
        // The change reaches the view on a later turn of the run loop: wait for it, not for a time.
        spin(until: { hosting.layoutSubtreeIfNeeded(); return seen.values.last == false })
        #expect(seen.values.last == false)
        window.contentView = nil
    }

    /// The scheme a toast's content reads (true for dark) in a root view hosted in a window of `appearance`.
    func schemeOfContent(look: NotchLook, appearance: NSAppearance.Name) -> Bool? {
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
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        spin(until: { hosting.layoutSubtreeIfNeeded(); return !seen.values.isEmpty })
        window.contentView = nil
        return seen.values.last
    }

    @Test func contentOnGlassKeepsTheSchemeOfItsWindowAsTheClassicNotchDoes() {
        for look in [NotchLook.liquidGlass, .classic] {
            #expect(schemeOfContent(look: look, appearance: .aqua) == false, "\(look) in a light window")
            #expect(schemeOfContent(look: look, appearance: .darkAqua) == true, "\(look) in a dark window")
        }
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

    @Test func thePanelKeepsTheSystemsAppearanceOnGlassAsOnTheClassicNotch() {
        // Glass in a panel that is forced dark reads as dark frosted glass, not as the system's; nothing is forced.
        for look in [NotchLook.liquidGlass, .classic] {
            let controller = makeController(theme: theme(look))
            defer { controller.close() }
            #expect(controller.appearance == nil, "\(look)")
        }
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

    @Test func theSurfaceModifierFillsWithBlackInTheClassicLookAndAsksForTheGlassPlanInTheOther() throws {
        // The 60 x 40 box sits at (10, 10) in the 80 x 60 image: (20, 20) is inside its rounded corner, (11, 11) outside it.
        let classic = try settled { () -> [CGFloat] in
            let bitmap = try draw(.solid)
            let inside = try #require(bitmap.colorAt(x: 20, y: 20)?.usingColorSpace(.sRGB))
            let outside = try #require(bitmap.colorAt(x: 11, y: 11))
            return [inside.alphaComponent, inside.redComponent, outside.alphaComponent]
        }
        #expect(classic[0] == 1 && classic[1] < 0.01, "black inside the shape")
        #expect(classic[2] == 0, "and only inside it")

        // On glass the modifier draws what the plan says (the glass is the window server's, and no black of ours), and a view with
        // glass is not read for its pixels here: see `settled`.
        let glass = NotchGlassPlan(surface: .liquidGlass(tinted: false), bubbleIDs: [], accent: .blue)
        #expect(glass.notch?.glass == Glass.regular)
        #expect(NotchGlassPlan(surface: .solid, bubbleIDs: [], accent: .blue).notch == nil)
        _ = try draw(.liquidGlass(tinted: false))
    }

    @Test func theSurfaceModifierLeavesTheSchemeOfItsContentAlone() throws {
        for surface in [NotchSurface.solid, .liquidGlass(tinted: false)] {
            let seen = Seen()
            _ = try draw(surface, seen: seen)
            #expect(seen.values.last == false, "the light scheme of the window is kept for \(surface)")
        }
    }

    // MARK: no scrim

    /// The pixel at `point` of a view rendered at scale 1, once two renders in a row agree.
    func pixel(of view: some View, at point: CGPoint, size: CGSize) throws -> NSColor {
        let components = try settled { () -> [CGFloat] in
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            let color = try #require(bitmap.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.sRGB))
            return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        }
        return NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: components[3])
    }

    @Test func theBackdropIsNothingOnGlassAndExactlyWhatItWasOtherwise() throws {
        let size = CGSize(width: 40, height: 40)
        let middle = CGPoint(x: 20, y: 20)
        let black = try pixel(of: NotchBackdrop(surface: .solid, bodyHeight: 10), at: middle, size: size)
        #expect(black.alphaComponent == 1 && black.redComponent == 0 && black.greenComponent == 0 && black.blueComponent == 0)
        // No black over the glass: it is the system's glass alone, which a dark scrim made look like dark frosted glass.
        for tinted in [false, true] {
            let clear = try pixel(of: NotchBackdrop(surface: .liquidGlass(tinted: tinted), bodyHeight: 10), at: middle, size: size)
            #expect(clear.alphaComponent == 0, "tinted \(tinted)")
        }
        // The classic blur keeps its solid strip at the top.
        let strip = try pixel(of: NotchBackdrop(surface: .material, bodyHeight: 10), at: CGPoint(x: 20, y: 3), size: size)
        #expect(strip.alphaComponent == 1 && strip.redComponent == 0)
    }

    @Test func aBubbleOnGlassIsTheGlassAloneAndOnTheClassicNotchIsStillBlack() throws {
        let center = ActivityCenter(scheduler: ManualScheduler())
        for index in 1...2 {
            center.set(LiveActivity(id: "a\(index)", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "\(index)"), from: "m")
        }
        let slots = ActivitySlot.bubbles(of: center, capacity: geometry.bubbleCapacity)
        let bubble = geometry.bubbleFrame(at: 0)
        let point = CGPoint(x: geometry.panelSize.width / 2 + bubble.midX, y: bubble.midY)
        func bubbles(_ surface: NotchSurface) -> some View {
            ActivityBubbles(slots: slots, geometry: geometry, label: { $0.id }, activate: { _ in }).environment(\.notchSurface, surface)
        }
        let size = CGSize(width: geometry.panelSize.width, height: geometry.bubbleDiameter)
        let classic = try pixel(of: bubbles(.solid), at: point, size: size)
        #expect(classic.alphaComponent == 1 && classic.redComponent == 0)
        #expect(try pixel(of: bubbles(.liquidGlass(tinted: false)), at: point, size: size).alphaComponent == 0)
    }
}
