import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// A canary, off unless asked for, that samples the glass SwiftUI makes for the notch while it animates, to see that it grows
/// about the notch's centre as the classic notch does. It reads the private layer class `CASDFElementLayer` and waits on the
/// run loop, so it is not part of the gate: a macOS update that renames the class, or a loaded machine, would fail it for no
/// reason of ours. The gating checks are `NotchGlassLayoutTests` (the layout the glass is placed from) and the plan tests.
///
/// Run it with `MYNOTCH_GLASS_CANARY=1 xcrun swift test --filter NotchGlassAnimationCanaryTests` in `Packages/NotchUI`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MYNOTCH_GLASS_CANARY"] != nil))
struct NotchGlassAnimationCanaryTests {
    func spin(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.004)) }
    }

    func shapes(in layer: CALayer, into found: inout [CALayer]) {
        if "\(type(of: layer))" == "CASDFElementLayer" { found.append(layer) }
        for sub in layer.sublayers ?? [] { shapes(in: sub, into: &found) }
    }

    /// The notch's glass is the widest shape; its frame in the hosting view, from the presentation layer.
    func notchFrame(in hosting: NSView) -> CGRect? {
        var found: [CALayer] = []
        if let root = hosting.layer { shapes(in: root, into: &found) }
        return found.map { layer -> CGRect in
            let presented = layer.presentation() ?? layer
            return presented.convert(presented.bounds, to: nil)
        }.max { $0.width < $1.width }
    }

    /// Applies each change in turn to a glass notch, letting it settle in between, and checks the glass's centre at every sample
    /// of every change. `bubbles` activities beside the primary one are live from the start.
    func sample(bubbles: Int, changes: [(String, (NotchViewModel, RegistryHarness) -> Void)], label: String) {
        let harness = RegistryHarness([])
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        let theme = NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        model.hasActivity = true
        harness.activities.set(LiveActivity(id: "a", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "a"), from: "m")
        for index in 0..<bubbles {
            harness.activities.set(
                LiveActivity(id: "b\(index)", priority: .low, leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "b"),
                from: ModuleID(stringLiteral: "m\(index)")
            )
        }
        model.bubbleCount = CompactAccessories.bubbleCount(activities: harness.activities, geometry: geometry)
        let hosting = FirstMouseHostingView(
            rootView: NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
        )
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        defer { window.contentView = nil }
        spin(0.8)
        let centre = geometry.panelSize.width / 2
        for (step, change) in changes {
            change(model, harness)
            let start = Date()
            var samples: [CGRect] = []
            while Date().timeIntervalSince(start) < 1.0 {
                spin(0.012)
                if let frame = notchFrame(in: hosting) { samples.append(frame) }
            }
            let name = "\(label), \(step)"
            #expect(samples.count > 5, "\(name): the glass was found while it animated")
            let worst = samples.map { abs($0.midX - centre) }.max() ?? 0
            let widths = Set(samples.map { Int($0.width) }).count
            print("CANARY \(name): \(samples.count) samples, \(widths) distinct widths, worst centre offset \(worst) pt")
            #expect(worst < 2, "\(name): the glass stays centred on the notch while it animates (worst \(worst) pt off)")
        }
    }

    @Test func hoverOpeningThenClosingTheNotchWithNoBubble() {
        sample(
            bubbles: 0,
            changes: [("hover open", { model, _ in model.open(tab: nil, onPurpose: false) }), ("close", { model, _ in model.close() })],
            label: "no bubble"
        )
    }

    @Test func openingThenClosingTheNotchWithBubbles() {
        sample(
            bubbles: 2,
            changes: [("open", { model, _ in model.open(tab: nil) }), ("close", { model, _ in model.close() })],
            label: "two bubbles"
        )
    }

    @Test func aToastComingAndGoing() {
        sample(
            bubbles: 0,
            changes: [
                ("toast", { model, _ in model.showToast(AnyView(Color.clear), duration: .seconds(60)) }),
                ("close", { model, _ in model.close() }),
            ],
            label: "no bubble"
        )
    }

    @Test func aStripAppearingAndTheListOpening() {
        sample(
            bubbles: 1,
            changes: [
                ("strip appears", { _, harness in
                    harness.activities.set(
                        LiveActivity(
                            id: "a", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), bottom: AnyView(Color.clear),
                            bottomHeight: 36, summary: "a"
                        ),
                        from: "m"
                    )
                }),
                ("list opens", { model, _ in model.showList() }),
                ("list closes", { model, _ in model.close() }),
            ],
            label: "one bubble"
        )
    }
}
