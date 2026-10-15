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
        for glassFloor in [0.2, 0.35] {
            // What the glass reads as once the scrim over it has darkened it.
            let floor = glassFloor * (1 - Double(NotchTokens.glassScrimOpacity))
            for (name, rgb, lightest) in ordinary + dark {
                func mixed(_ channel: UInt8) -> Double { opacity * Double(channel) / 255 + (1 - opacity) * floor }
                let capsule = luminance(mixed(rgb.red), mixed(rgb.green), mixed(rgb.blue))
                #expect(contrast(1, capsule) >= 3, "white icon on the \(name) capsule over \(glassFloor) grey")
                let against = contrast(luminance(floor, floor, floor), capsule)
                #expect(against >= (glassFloor == 0.35 ? lightest : 1.2), "the \(name) capsule against \(glassFloor) grey is \(against)")
            }
        }
    }

    // MARK: text on glass

    /// `ImageRenderer` hands its pixels back lighter than the colours it was given, by a power of 0.8 (an opaque sRGB grey of
    /// 0.5 reads as 0.574), so a pixel is raised to 1.25 to be compared with a colour. That is applied to white drawn over
    /// black only, to read how much of white a style is: it gives the 0.55 and 0.85 that macOS defines for the system's
    /// secondary and primary label in a dark appearance. Everything else here is plain arithmetic on those alphas.
    static let rendererCurve = 1.25

    /// How much of white `style` is, drawn over black in the dark scheme the notch has on glass.
    func effectiveAlpha(of style: AnyShapeStyle) throws -> Double {
        let view = ZStack { Color.black; Rectangle().fill(style).frame(width: 8, height: 8) }
            .environment(\.colorScheme, .dark).frame(width: 12, height: 12)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return pow(Double(try #require(bitmap.colorAt(x: 6, y: 6)?.usingColorSpace(.sRGB)).redComponent), Self.rendererCurve)
    }

    @Test func theMeasurementOfAStylesWhiteReadsKnownAlphasBack() throws {
        for alpha in [0.25, 0.6, 1.0] {
            let read = try effectiveAlpha(of: AnyShapeStyle(Color.white.opacity(alpha)))
            #expect(abs(read - alpha) < 0.02, "white at \(alpha) read as \(read): the renderer's tone curve may have changed")
        }
    }

    /// WCAG contrast of text of `alpha` of white over what the glass reads as, `glassGrey` (an estimate: nothing is
    /// captured here), after the scrim has darkened it by `scrim`.
    func textContrast(alpha: Double, glassGrey: Double, scrim: Double) -> Double {
        let background = glassGrey * (1 - scrim)
        let text = alpha + (1 - alpha) * background
        return contrast(luminance(text, text, text), luminance(background, background, background))
    }

    @Test func textOnGlassReadsAtFourAndAHalfToOneOverTheGlassFloorsOfTheReport() throws {
        // 12 pt text needs 4.5:1. The two floors are the report's estimates of the lightest and the usual glass; the module
        // text is white at 0.6 (every module draws with it), the notch's own rows are the glass's secondary style.
        let glass = NotchSurface.liquidGlass(tinted: false)
        let scrim = Double(NotchTokens.glassScrimOpacity)
        let moduleSecondary = try effectiveAlpha(of: AnyShapeStyle(NotchTokens.secondaryText))
        let ownSecondary = try effectiveAlpha(of: glass.secondaryStyle)
        let modulePrimary = try effectiveAlpha(of: AnyShapeStyle(NotchTokens.primaryText))
        let ownPrimary = try effectiveAlpha(of: glass.primaryStyle)
        for floor in [0.2, 0.35] {
            #expect(textContrast(alpha: moduleSecondary, glassGrey: floor, scrim: scrim) >= 4.5, "module text over \(floor) grey")
            #expect(textContrast(alpha: ownSecondary, glassGrey: floor, scrim: scrim) >= 4.5, "the notch's own secondary text over \(floor) grey")
            #expect(textContrast(alpha: modulePrimary, glassGrey: floor, scrim: scrim) >= 7, "module primary text over \(floor) grey")
            #expect(textContrast(alpha: ownPrimary, glassGrey: floor, scrim: scrim) >= 7, "the notch's own primary text over \(floor) grey")
        }
    }

    @Test func theNotchsOwnSecondaryTextOnGlassIsAsStrongAsTheModulesAndStillTheSystemsStyle() throws {
        let glass = NotchSurface.liquidGlass(tinted: false)
        // The system's plain secondary label (0.55 of white) would be weaker than the 0.6 every module draws with.
        #expect(try effectiveAlpha(of: glass.secondaryStyle) >= effectiveAlpha(of: AnyShapeStyle(NotchTokens.secondaryText)) - 0.01)
        #expect(try effectiveAlpha(of: AnyShapeStyle(.secondary)) < effectiveAlpha(of: AnyShapeStyle(NotchTokens.secondaryText)))
    }

    @Test func withoutTheScrimTheModuleTextWouldNotReadOnTheLightestGlass() throws {
        let alpha = try effectiveAlpha(of: AnyShapeStyle(NotchTokens.secondaryText))
        #expect(textContrast(alpha: alpha, glassGrey: 0.35, scrim: 0) < 4.5)
        #expect(textContrast(alpha: alpha, glassGrey: 0.35, scrim: Double(NotchTokens.glassScrimOpacity)) >= 4.5)
    }

    @Test func theScrimIsAHintOfBlackNotACoatOfIt() {
        #expect(NotchTokens.glassScrimOpacity > 0 && NotchTokens.glassScrimOpacity <= 0.35)
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

    @Test func theSurfaceModifierFillsWithBlackInTheClassicLookAndHasAScrimOnGlassInTheOther() throws {
        // The 60 x 40 box sits at (10, 10) in the 80 x 60 image: (20, 20) is inside its rounded corner, (11, 11) outside it.
        let classic = try draw(.solid)
        let inside = try #require(classic.colorAt(x: 20, y: 20))
        #expect(inside.alphaComponent == 1 && inside.redComponent == 0)
        #expect(try #require(classic.colorAt(x: 11, y: 11)).alphaComponent == 0, "inside its shape only")

        // On glass the shape holds the window server's glass, which offscreen is nothing, and under the content a scrim: black
        // at `glassScrimOpacity`, clipped to the shape like the content, and under what is drawn on it.
        let glass = try draw(.liquidGlass(tinted: false))
        let scrim = try #require(glass.colorAt(x: 20, y: 20)?.usingColorSpace(.sRGB))
        #expect(abs(scrim.alphaComponent - NotchTokens.glassScrimOpacity) < 0.02)
        #expect(scrim.redComponent == 0 && scrim.greenComponent == 0 && scrim.blueComponent == 0)
        #expect(try #require(glass.colorAt(x: 11, y: 11)).alphaComponent == 0, "the scrim is clipped to the shape")
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

    // MARK: the scrim

    func alpha(of view: some View, at point: CGPoint, size: CGSize) throws -> NSColor {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return try #require(bitmap.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.sRGB))
    }

    @Test func theBackdropIsAScrimOnGlassAndExactlyWhatItWasOtherwise() throws {
        let size = CGSize(width: 40, height: 40)
        let middle = CGPoint(x: 20, y: 20)
        let black = try alpha(of: NotchBackdrop(surface: .solid, bodyHeight: 10), at: middle, size: size)
        #expect(black.alphaComponent == 1 && black.redComponent == 0 && black.greenComponent == 0 && black.blueComponent == 0)
        let scrim = try alpha(of: NotchBackdrop(surface: .liquidGlass(tinted: false), bodyHeight: 10), at: middle, size: size)
        #expect(abs(scrim.alphaComponent - NotchTokens.glassScrimOpacity) < 0.02)
        #expect(scrim.redComponent == 0 && scrim.greenComponent == 0 && scrim.blueComponent == 0)
        let tintedScrim = try alpha(of: NotchBackdrop(surface: .liquidGlass(tinted: true), bodyHeight: 10), at: middle, size: size)
        #expect(tintedScrim.alphaComponent == scrim.alphaComponent, "the scrim is black whatever the tint")
        // The classic blur keeps its solid strip at the top.
        let strip = try alpha(of: NotchBackdrop(surface: .material, bodyHeight: 10), at: CGPoint(x: 20, y: 3), size: size)
        #expect(strip.alphaComponent == 1 && strip.redComponent == 0)
    }

    @Test func aBubbleOnGlassHasTheSameScrimAndOnTheClassicNotchIsStillBlack() throws {
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
        let classic = try alpha(of: bubbles(.solid), at: point, size: size)
        #expect(classic.alphaComponent == 1 && classic.redComponent == 0)
        let glass = try alpha(of: bubbles(.liquidGlass(tinted: false)), at: point, size: size)
        #expect(abs(glass.alphaComponent - NotchTokens.glassScrimOpacity) < 0.02)
        #expect(glass.redComponent == 0 && glass.greenComponent == 0 && glass.blueComponent == 0)
    }
}
