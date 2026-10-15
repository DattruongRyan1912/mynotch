import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// What the notch draws with: the accent resolved from the setting and from macOS, and whether the open notch is glass.
@Suite struct NotchThemeTests {
    typealias RGB = NotchAccent.RGB

    /// What macOS says its accent is; a test changes it and says so on its own notification centre.
    final class FakeSystem {
        var accent = RGB(red: 10, green: 132, blue: 255)
    }

    /// Flags that something a view read has changed.
    nonisolated final class Changed: @unchecked Sendable {
        nonisolated(unsafe) var value = false
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    let settings = SettingsStore(defaults: makeIsolatedDefaults())
    let system = FakeSystem()
    let center = NotificationCenter()

    func makeTheme() -> NotchTheme {
        NotchTheme(settings: settings, systemAccent: { [system] in system.accent }, notifications: center)
    }

    // MARK: accent

    @Test func byDefaultTheNotchUsesTheSystemAccent() {
        let theme = makeTheme()
        #expect(theme.resolvedAccent == system.accent)
    }

    @Test func aPaletteColourOrACustomOneReplacesIt() {
        let theme = makeTheme()
        settings.set(.palette(.orange), for: InterfaceSettings.accent)
        #expect(theme.resolvedAccent == NotchAccent.Palette.orange.rgb)
        settings.set(.custom(RGB(red: 124, green: 92, blue: 255)), for: InterfaceSettings.accent)
        #expect(theme.resolvedAccent == RGB(red: 124, green: 92, blue: 255))
        settings.set(.system, for: InterfaceSettings.accent)
        #expect(theme.resolvedAccent == system.accent)
    }

    @Test func theAccentAsAColourIsTheResolvedOne() {
        let theme = makeTheme()
        settings.set(.palette(.green), for: InterfaceSettings.accent)
        let green = NSColor(theme.accent).usingColorSpace(.sRGB)
        #expect(green.map { UInt8(($0.greenComponent * 255).rounded()) } == NotchAccent.Palette.green.rgb.green)
    }

    @Test func aViewThatReadTheAccentIsToldWhenTheSettingChanges() {
        let theme = makeTheme()
        let changed = Changed()
        withObservationTracking { _ = theme.accent } onChange: { changed.value = true }
        #expect(!changed.value)
        settings.set(.palette(.red), for: InterfaceSettings.accent)
        #expect(changed.value)
    }

    @Test func aViewIsToldWhenMacOSChangesItsAccentAndSeesTheNewOne() async {
        let theme = makeTheme()
        let changed = Changed()
        withObservationTracking { _ = theme.accent } onChange: { changed.value = true }
        system.accent = RGB(red: 255, green: 69, blue: 58)
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        #expect(await eventually { changed.value })
        #expect(theme.resolvedAccent == RGB(red: 255, green: 69, blue: 58))
    }

    @Test func aFixedAccentIsNotTouchedWhenMacOSChangesItsOwn() async {
        let theme = makeTheme()
        settings.set(.palette(.purple), for: InterfaceSettings.accent)
        system.accent = RGB(red: 1, green: 2, blue: 3)
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(theme.resolvedAccent == NotchAccent.Palette.purple.rgb)
    }

    // MARK: glass

    @Test func glassIsOffUntilTheUserTurnsItOn() {
        let theme = makeTheme()
        #expect(!theme.glass)
        settings.set(true, for: InterfaceSettings.glass)
        #expect(theme.glass)
    }

    @Test func glassIsOnlyForTheExpandedNotch() {
        for state in [NotchState.open(nil), .open("a"), .toast] {
            #expect(NotchTheme.showsGlass(enabled: true, state: state), "\(state)")
            #expect(!NotchTheme.showsGlass(enabled: false, state: state), "\(state)")
        }
    }

    @Test func theCollapsedNotchIsNeverGlassSoItKeepsMatchingTheCutout() {
        for state in [NotchState.closed, .compact] {
            #expect(!NotchTheme.showsGlass(enabled: true, state: state), "\(state)")
            #expect(!NotchTheme.showsGlass(enabled: false, state: state), "\(state)")
        }
    }

    // MARK: drawn

    /// The pill and the open notch drawn offscreen, with the colour the pixel at (x, y) has.
    func pixel(of view: some View, at point: CGPoint, size: CGSize) throws -> NSColor {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return try #require(bitmap.colorAt(x: Int(point.x), y: Int(point.y)))
    }

    func rootView(state: (NotchViewModel) -> Void, theme: NotchTheme?) -> (NotchRootView, NotchGeometry) {
        let harness = RegistryHarness([])
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        state(model)
        return (NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme), geometry)
    }

    @Test func theCollapsedNotchIsOpaqueBlackEvenWithGlassOn() throws {
        settings.set(true, for: InterfaceSettings.glass)
        let (view, geometry) = rootView(state: { _ in }, theme: makeTheme())
        // Inside the pill, a little below the top and near its centre line (the notch is 1.5 pt left of the middle).
        let point = CGPoint(x: geometry.panelSize.width / 2 + geometry.centerOffset, y: geometry.notchSize.height - 6)
        let color = try pixel(of: view, at: point, size: geometry.panelSize)
        #expect(color.alphaComponent == 1)
        #expect(color.redComponent == 0 && color.greenComponent == 0 && color.blueComponent == 0)
    }

    @Test func theNotchBodyStaysOpaqueBlackWhenGlassIsOnAndTheNotchIsOpen() throws {
        settings.set(true, for: InterfaceSettings.glass)
        let (view, geometry) = rootView(state: { $0.open(tab: nil) }, theme: makeTheme())
        // Behind the hardware notch there is nothing to see through to: its strip stays solid so the two join.
        let point = CGPoint(x: geometry.panelSize.width / 2 + geometry.centerOffset, y: geometry.notchSize.height / 2)
        let color = try pixel(of: view, at: point, size: geometry.panelSize)
        #expect(color.alphaComponent == 1)
        #expect(color.redComponent == 0 && color.greenComponent == 0 && color.blueComponent == 0)
    }

    /// A view that fills itself with the accent from the environment, for a toast's content.
    struct AccentProbe: View {
        @Environment(\.notchAccent) private var accent
        var body: some View { Rectangle().fill(accent) }
    }

    /// A view that fills itself with the tint, which the system controls of a tab use.
    struct TintProbe: View {
        var body: some View { Rectangle().fill(.tint) }
    }

    /// Whether any pixel of the open notch (a toast of `content`) is `target`, near enough.
    func draws(_ content: AnyView, theme: NotchTheme?, size: CGSize? = nil, target: RGB) throws -> Bool {
        let (view, geometry) = rootView(state: { $0.showToast(content, duration: .seconds(60)) }, theme: theme)
        let size = size ?? geometry.panelSize
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent == 1 else { continue }
                let close = abs(color.redComponent * 255 - Double(target.red)) < 3
                    && abs(color.greenComponent * 255 - Double(target.green)) < 3 && abs(color.blueComponent * 255 - Double(target.blue)) < 3
                if close { return true }
            }
        }
        return false
    }

    @Test func theNotchGivesItsContentTheAccentTheUserPicked() throws {
        settings.set(.custom(RGB(red: 250, green: 20, blue: 20)), for: InterfaceSettings.accent)
        let target = RGB(red: 250, green: 20, blue: 20)
        #expect(try draws(AnyView(AccentProbe()), theme: makeTheme(), target: target))
        #expect(try !draws(AnyView(AccentProbe()), theme: nil, target: target))
    }

    @Test func theNotchGivesItsContentTheSystemAccentWhenNothingWasPicked() throws {
        #expect(try draws(AnyView(AccentProbe()), theme: makeTheme(), target: system.accent))
    }

    @Test func theTintOfTheSystemControlsInATabFollowsTheAccentToo() throws {
        settings.set(.custom(RGB(red: 20, green: 220, blue: 40)), for: InterfaceSettings.accent)
        #expect(try draws(AnyView(TintProbe()), theme: makeTheme(), target: RGB(red: 20, green: 220, blue: 40)))
    }

    @Test func withoutAThemeContentGetsTheNotchsOwnPurple() throws {
        let purple = RGB(red: 125, green: 92, blue: 255)
        #expect(try draws(AnyView(AccentProbe()), theme: nil, target: purple))
    }

    @Test func theSelectedTabIsMarkedWithTheAccent() throws {
        let tabs = [
            NotchTab(id: "a", title: "A", systemImage: "circle", content: AnyView(EmptyView())),
            NotchTab(id: "b", title: "B", systemImage: "square", content: AnyView(EmptyView())),
        ]
        func accentPixels(_ accent: Color, selected: ModuleID?) throws -> Int {
            let view = TabBar(tabs: tabs, selected: selected) { _ in }.environment(\.notchAccent, accent).background(Color.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            var count = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                    if color.redComponent > color.greenComponent + 0.1, color.redComponent > color.blueComponent + 0.1 { count += 1 }
                }
            }
            return count
        }
        let red = Color(.sRGB, red: 1, green: 0, blue: 0)
        #expect(try accentPixels(red, selected: "a") > 100)
        #expect(try accentPixels(red, selected: nil) == 0)
    }
}
