import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// Where the glass family puts the notch. A `GlassEffectContainer` places each glass shape from the layout of its content, so
/// if that content is only as big as the notch (which animates its size), the glass is anchored to the content's edge instead
/// of growing about the notch's centre: with no bubble to hold the row at the panel's width, the glass of an opening notch grew
/// out of its right corner. The family's content is therefore always as big as the panel, with the notch at its top centre,
/// whatever the notch's own size is.
@Suite struct NotchGlassLayoutTests {
    let panel = CGSize(width: 300, height: 200)
    let probe = CGSize(width: 50, height: 20)

    /// Collects the frame a probe has in its window.
    final class Frame {
        var value: CGRect?
    }

    func window(_ view: some View) -> (NSHostingView<AnyView>, NSWindow) {
        let hosting = NSHostingView(rootView: AnyView(view))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: panel), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func probeFrame(plan: NotchGlassPlan, size: CGSize? = nil) -> CGRect? {
        let size = size ?? probe
        let frame = Frame()
        let (_, window) = window(
            NotchGlassFamily(plan) {
                Color.clear.frame(width: size.width, height: size.height)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.value = $0 }
            }
        )
        defer { window.contentView = nil }
        return frame.value
    }

    @Test func theNotchSitsAtTheTopCentreOfThePanelWhateverItsSizeAndWhetherOrNotThereIsGlass() throws {
        let glass = NotchGlassPlan(surface: .liquidGlass(tinted: false), bubbleIDs: [], accent: .blue)
        for plan in [NotchGlassPlan.none, glass] {
            for size in [CGSize(width: 50, height: 20), CGSize(width: 185, height: 32), CGSize(width: 240, height: 180)] {
                let frame = try #require(probeFrame(plan: plan, size: size))
                #expect(abs(frame.midX - panel.width / 2) < 0.5, "centred for \(size) with\(plan.usesContainer ? "" : "out") glass: \(frame)")
                #expect(abs(frame.minY) < 0.5, "at the top for \(size) with\(plan.usesContainer ? "" : "out") glass: \(frame)")
            }
        }
    }

    /// The root view with glass or without, hosted at the panel's size: where a probe in the notch's content is.
    func rootProbeFrame(look: NotchLook, state: (NotchViewModel, RegistryHarness) -> Void) throws -> CGRect {
        let harness = RegistryHarness([])
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        settings.set(look, for: InterfaceSettings.look)
        let theme = NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        let frame = Frame()
        let content = Color.clear.frame(width: 20, height: 14)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.value = $0 }
        harness.activities.set(
            LiveActivity(id: "a", leading: AnyView(Color.clear), trailing: AnyView(content), summary: "a"), from: "m"
        )
        state(model, harness)
        let hosting = NSHostingView(
            rootView: NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
        )
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        return try #require(frame.value)
    }

    @Test func theCollapsedNotchContentIsWhereTheClassicLookPutsItWithAndWithoutBubbles() throws {
        for bubbles in [false, true] {
            func frame(_ look: NotchLook) throws -> CGRect {
                try rootProbeFrame(look: look) { model, harness in
                    model.hasActivity = true
                    if bubbles {
                        harness.activities.set(
                            LiveActivity(id: "b", priority: .low, leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "b"), from: "n"
                        )
                        model.bubbleCount = 1
                    }
                }
            }
            #expect(try frame(.liquidGlass) == frame(.classic), "bubbles: \(bubbles)")
        }
    }
}
