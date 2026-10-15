import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// `debug.glass.active`: the notch panel's glass drawn as an active window's, which is a question of the window's key
/// *appearance*, never of key status. These tests pin that key status does not move, that the hook does nothing when its method
/// is missing or is not what is expected, that nothing is hooked by default and on the classic look, and that the appearance comes
/// back after AppKit takes it away. What the glass then looks like is for the eye; `ActiveGlassLayerCanaryTests` reads the glass's
/// own parameters, and is off unless asked for.
@Suite struct ActiveGlassTests {
    /// The appearance flag of AppKit's window theme, which is what `ActiveGlassAppearance` sets; nil if this macOS has not got it.
    func hasKeyAppearance(_ window: NSWindow) -> Bool? {
        guard window.responds(to: NSSelectorFromString("hasKeyAppearance")) else { return nil }
        return window.value(forKey: "hasKeyAppearance") as? Bool
    }

    /// Everything that says whether a window is key, or could be.
    struct KeyState: Equatable {
        let isKey: Bool
        let isMain: Bool
        let canBecomeKey: Bool
        let canBecomeMain: Bool
        let appKeyWindow: ObjectIdentifier?
        let appIsActive: Bool
        let allowsKeyStatus: Bool

        init(_ panel: NotchPanel) {
            isKey = panel.isKeyWindow
            isMain = panel.isMainWindow
            canBecomeKey = panel.canBecomeKey
            canBecomeMain = panel.canBecomeMain
            appKeyWindow = NSApplication.shared.keyWindow.map(ObjectIdentifier.init)
            appIsActive = NSApplication.shared.isActive
            allowsKeyStatus = panel.allowsKeyStatus
        }
    }

    /// A panel with a notification center of its own: the tests run side by side in one process, and the notifications one posts must
    /// not reach the panel of another.
    func makePanel(notifications: NotificationCenter = NotificationCenter()) -> NotchPanel {
        NotchPanel(frame: CGRect(x: 0, y: 0, width: 200, height: 100), notifications: notifications)
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: the hook exists, and does what it is for

    @Test func thisMacOSHasTheMethodsTheHookIsMadeOf() {
        // The day this fails, the switch silently does nothing: look at `ActiveGlassAppearance` and the probe in U3c-report.md.
        #expect(ActiveGlassAppearance.detect() != nil)
    }

    @Test func givingAPanelTheKeyAppearanceLeavesItsKeyStatusExactlyAsItWas() throws {
        let panel = makePanel()
        defer { panel.close() }
        let appearance = try #require(ActiveGlassAppearance.detect())
        let before = KeyState(panel)
        #expect(hasKeyAppearance(panel) == false, "this macOS has the flag, and a fresh panel has not got it")

        #expect(appearance.acquire(on: panel))
        #expect(hasKeyAppearance(panel) == true, "the glass is to be drawn as an active window's")
        #expect(KeyState(panel) == before, "and nothing about key status moved")
        #expect(!panel.isKeyWindow)
        #expect(!panel.canBecomeKey)
        #expect(panel.allowsKeyStatus == false)
        #expect(NSApplication.shared.keyWindow !== panel)

        #expect(appearance.release(on: panel))
        #expect(hasKeyAppearance(panel) == false)
        #expect(KeyState(panel) == before)
    }

    @Test func aPanelThatMayBecomeKeyIsStillNotKeyWithTheAppearanceAndItsPermissionIsUntouched() throws {
        let panel = makePanel()
        defer { panel.close() }
        panel.allowsKeyStatus = true
        let appearance = try #require(ActiveGlassAppearance.detect())
        appearance.acquire(on: panel)
        #expect(!panel.isKeyWindow, "being allowed to be key is not being key")
        #expect(panel.allowsKeyStatus == true, "the permission is the keyboard policy's, not ours")
        #expect(panel.canBecomeKey)
    }

    // MARK: guarded

    @Test func withNoSuchMethodTheSwitchDoesNothing() throws {
        let panel = makePanel()
        defer { panel.close() }
        let missing = ActiveGlassAppearance(acquireName: "mynotchNoSuchMethod", resignName: "mynotchNoSuchMethodEither")
        let before = KeyState(panel)
        #expect(!missing.isAvailable(on: NSWindow.self))
        #expect(!missing.acquire(on: panel))
        #expect(!missing.release(on: panel))
        panel.activeGlass = missing
        panel.refreshActiveGlass(afterAppKitHasFinished: true)
        panel.resignKey()
        #expect(hasKeyAppearance(panel) == false)
        #expect(KeyState(panel) == before)
        panel.activeGlass = nil
    }

    @Test func aMethodThatIsNotVoidTakingNothingIsNeverCalled() {
        // `isKeyWindow` exists but returns a BOOL: calling it as a void method is not what the hook was written against.
        let wrongShape = ActiveGlassAppearance(acquireName: "isKeyWindow", resignName: "resignKeyAppearance")
        #expect(!wrongShape.isAvailable(on: NSWindow.self))
        let panel = makePanel()
        defer { panel.close() }
        #expect(!wrongShape.acquire(on: panel))
        let oneArgument = ActiveGlassAppearance(acquireName: "setTitle:", resignName: "resignKeyAppearance")
        #expect(!oneArgument.isAvailable(on: NSWindow.self))
        #expect(!oneArgument.acquire(on: panel))
        #expect(hasKeyAppearance(panel) == false)
    }

    @Test func aKeyPanelIsNotReleasedBecauseItHasTheAppearanceByRight() throws {
        // Not made key here (that would take the keyboard from whoever has it): `release` asks the window, so a window that
        // says it is key is the case to cover, and a subclass says so.
        final class KeyLiar: NSPanel {
            override var isKeyWindow: Bool { true }
        }
        let liar = KeyLiar(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        defer { liar.close() }
        let appearance = try #require(ActiveGlassAppearance.detect())
        appearance.acquire(on: liar)
        #expect(!appearance.release(on: liar))
        #expect(hasKeyAppearance(liar) == true)
        // Taken away by AppKit's own method, which is what a real resignation does.
        liar.perform(NSSelectorFromString("resignKeyAppearance"))
    }

    // MARK: the panel

    @Test func nothingIsHookedByDefault() {
        let panel = makePanel()
        defer { panel.close() }
        #expect(panel.activeGlass == nil)
        panel.refreshActiveGlass(afterAppKitHasFinished: true)
        panel.resignKey()
        #expect(hasKeyAppearance(panel) == false)
        #expect(!panel.isKeyWindow)
    }

    @Test func aPanelWithTheSwitchHasTheAppearanceAtOnceAndLosesItWhenTheSwitchGoes() throws {
        let panel = makePanel()
        defer { panel.close() }
        let before = KeyState(panel)
        let appearance = try #require(ActiveGlassAppearance.detect())
        panel.activeGlass = appearance
        #expect(hasKeyAppearance(panel) == true)
        panel.activeGlass = nil
        #expect(hasKeyAppearance(panel) == false)
        #expect(KeyState(panel) == before)
    }

    @Test func theAppearanceComesBackWhenAppKitTakesItAwayAndNeverMakesThePanelKey() async throws {
        let center = NotificationCenter()
        let panel = makePanel(notifications: center)
        defer { panel.close() }
        let appearance = try #require(ActiveGlassAppearance.detect())
        panel.activeGlass = appearance
        let before = KeyState(panel)

        // The panel resigning key (public API; the panel is not key, and AppKit resigns it anyway).
        appearance.release(on: panel)
        #expect(hasKeyAppearance(panel) == false)
        panel.resignKey()
        #expect(hasKeyAppearance(panel) == true)

        // Each of the things that make AppKit take it back, as AppKit announces them.
        for name in [NSWindow.didResignKeyNotification, NSWindow.didChangeScreenNotification, NSWindow.didChangeOcclusionStateNotification] {
            appearance.release(on: panel)
            center.post(name: name, object: panel)
            #expect(await eventually { hasKeyAppearance(panel) == true }, "\(name.rawValue)")
        }
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification] {
            appearance.release(on: panel)
            center.post(name: name, object: NSApplication.shared)
            #expect(await eventually { hasKeyAppearance(panel) == true }, "\(name.rawValue)")
        }
        #expect(KeyState(panel) == before)
    }

    @Test func aNotificationOfAnotherWindowDoesNotConcernThePanel() async throws {
        let center = NotificationCenter()
        let panel = makePanel(notifications: center)
        defer { panel.close() }
        let other = makePanel(notifications: center)
        defer { other.close() }
        let appearance = try #require(ActiveGlassAppearance.detect())
        panel.activeGlass = appearance
        appearance.release(on: panel)
        center.post(name: NSWindow.didResignKeyNotification, object: other)
        center.post(name: NSWindow.didChangeScreenNotification, object: other)
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: other)
        try await Task.sleep(for: .milliseconds(100))
        #expect(hasKeyAppearance(panel) == false, "the panel's own notifications are the ones it listens to")
    }

    @Test func aPanelWithoutTheSwitchIgnoresWhatWouldBringTheAppearanceBack() async throws {
        let center = NotificationCenter()
        let panel = makePanel(notifications: center)
        defer { panel.close() }
        center.post(name: NSWindow.didResignKeyNotification, object: panel)
        center.post(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
        try await Task.sleep(for: .milliseconds(100))
        #expect(hasKeyAppearance(panel) == false)
        // And one whose switch went stops listening.
        let appearance = try #require(ActiveGlassAppearance.detect())
        panel.activeGlass = appearance
        panel.activeGlass = nil
        center.post(name: NSWindow.didResignKeyNotification, object: panel)
        center.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        try await Task.sleep(for: .milliseconds(100))
        #expect(hasKeyAppearance(panel) == false)
    }

    // MARK: the window controller

    let harness = RegistryHarness([])

    func theme(_ look: NotchLook) -> NotchTheme {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        settings.set(look, for: InterfaceSettings.look)
        return NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
    }

    func makeController(theme: NotchTheme?, _ switches: NotchGlassSwitches?) -> NotchWindowController {
        NotchWindowController(
            displayID: 1, screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities,
            delays: { (.milliseconds(150), .milliseconds(300)) },
            captureHiding: { .never }, swipesBetweenTabs: { true },
            theme: theme, glassSwitches: switches ?? .default
        )
    }

    @Test func theSwitchHooksThePanelOnGlassOnly() async throws {
        let on = NotchGlassSwitches(active: true)
        let glass = makeController(theme: theme(.liquidGlass), on)
        defer { glass.close() }
        #expect(await eventually { glass.activeGlass != nil }, "glass, switch on: hooked")
        #expect(!glass.panelIsKey, "and the panel is not key")

        let classic = makeController(theme: theme(.classic), on)
        defer { classic.close() }
        let off = makeController(theme: theme(.liquidGlass), NotchGlassSwitches(active: false))
        defer { off.close() }
        let byDefault = makeController(theme: theme(.liquidGlass), nil)
        defer { byDefault.close() }
        let noTheme = makeController(theme: nil, on)
        defer { noTheme.close() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(classic.activeGlass == nil, "the classic look: unchanged")
        #expect(off.activeGlass == nil)
        #expect(byDefault.activeGlass == nil, "switch off: nothing hooked")
        #expect(noTheme.activeGlass == nil)
        for controller in [classic, off, byDefault, noTheme] { #expect(!controller.panelIsKey) }
    }

    @Test func theHookFollowsTheLookWhileTheAppRuns() async throws {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        settings.set(.classic, for: InterfaceSettings.look)
        let theme = NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let controller = makeController(theme: theme, NotchGlassSwitches(active: true))
        defer { controller.close() }
        try await Task.sleep(for: .milliseconds(150))
        #expect(controller.activeGlass == nil)
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        #expect(await eventually { controller.activeGlass != nil })
        settings.set(.classic, for: InterfaceSettings.look)
        #expect(await eventually { controller.activeGlass == nil })
        #expect(!controller.panelIsKey)
    }

    @Test func theKeyboardPolicyIsNotAffectedByTheHook() async throws {
        let controller = makeController(theme: theme(.liquidGlass), NotchGlassSwitches(active: true))
        defer { controller.close() }
        #expect(await eventually { controller.activeGlass != nil })
        try await Task.sleep(for: .milliseconds(100))
        #expect(!controller.panelIsKey, "the panel is not key, and takes no keyboard")
        // The window is never ordered in here (it would show on the user's screen): the hook is the same one that runs after the
        // panel is ordered front, and `ActiveGlassLayerCanaryTests` orders one far off screen.
        #expect(controller.activeGlass != nil)
    }
}

/// The glass's own parameters in a hosted layer tree: a window that is not key, and the same window with the key appearance. It
/// reads private layer classes and names (`CAFilter` `glassBackground` and its inputs), and it orders a transparent panel in far
/// off screen, so it is not part of the gate: run it with
/// `MYNOTCH_GLASS_CANARY=1 xcrun swift test --filter ActiveGlassLayerCanaryTests` in `Packages/NotchUI`. (A window made key on
/// purpose has the same parameters as the appearance gives; that was probed once, outside the suite, because it takes the keyboard
/// from whoever has it, and is in the report.)
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MYNOTCH_GLASS_CANARY"] != nil))
struct ActiveGlassLayerCanaryTests {
    func spin(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.004)) }
    }

    /// The numbers of the first `glassBackground` filter in the tree, by name, as text.
    func parameters(in layer: CALayer?) -> [String: String] {
        var found: [String: String] = [:]
        func walk(_ layer: CALayer) {
            for filter in layer.filters ?? [] where found.isEmpty {
                let object = filter as AnyObject
                guard "\(object.value(forKey: "name") ?? "")" == "glassBackground",
                      let keys = (object as? NSObject)?.value(forKey: "inputKeys") as? [String] else { continue }
                for key in keys where !key.contains("FillColor") { found[key] = "\((object as? NSObject)?.value(forKey: key) ?? "")" }
            }
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        if let layer { walk(layer) }
        return found
    }

    @Test func theGlassTakesTheParametersOfAnActiveWindowWithTheAppearanceAndLosesThemWithout() throws {
        let panel = NotchPanel(frame: CGRect(x: -30000, y: -30000, width: 400, height: 200))
        defer { panel.close() }
        panel.alphaValue = 0
        let hosting = NSHostingView(rootView: GlassEffectContainer(spacing: 4) {
            Color.clear.frame(width: 300, height: 120).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        }.frame(width: 400, height: 200))
        panel.contentView = hosting
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        spin(0.5)
        let appearance = try #require(ActiveGlassAppearance.detect())

        let inactive = parameters(in: hosting.layer)
        try #require(!inactive.isEmpty, "the filter was found")
        appearance.acquire(on: panel)
        spin(0.4)
        let active = parameters(in: hosting.layer)
        #expect(!panel.isKeyWindow)
        #expect(NSApplication.shared.keyWindow == nil)
        let interesting = ["inputBleedBlurRadius", "inputBleedOpacity", "inputOuterRefractionAmount", "inputRefractionOpacity", "inputShadowOpacity"]
        print("CANARY subdued: \(interesting.map { "\($0)=\(inactive[$0] ?? "-")" })")
        print("CANARY active:  \(interesting.map { "\($0)=\(active[$0] ?? "-")" })")
        #expect(active != inactive, "the glass changed")
        #expect(Double(active["inputRefractionOpacity"] ?? "") ?? 0 > Double(inactive["inputRefractionOpacity"] ?? "") ?? 0)
        #expect(Double(active["inputBleedBlurRadius"] ?? "") ?? 0 > Double(inactive["inputBleedBlurRadius"] ?? "") ?? 0)

        appearance.release(on: panel)
        spin(0.3)
        #expect(parameters(in: hosting.layer) == inactive, "taken away, the subdued parameters are back")
    }
}
