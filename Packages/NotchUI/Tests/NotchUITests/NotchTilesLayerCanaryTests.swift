import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

private final class TabModule: FeatureModule {
    let descriptor: ModuleDescriptor
    init(_ id: ModuleID, order: Int) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: true, order: order)
    }
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: "T", systemImage: "circle", preferredHeight: 190, content: AnyView(Color.clear))
    }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

/// The glass of the notch as the layer tree has it, for what no public API can say: that the collapsed notch's content is drawn above
/// its glass (U3e problem 1), where the tiles' glass starts and ends, and that there is never a moment with no glass at all. It reads
/// private layer classes (`SDFLayer`, `CASDFElementLayer`) and samples the run loop, so it is not part of the gate: run it with
/// `MYNOTCH_GLASS_CANARY=1 xcrun swift test --filter NotchTilesLayerCanaryTests` in `Packages/NotchUI`. Its sampler waits with
/// `Task.sleep`; a sampler that spins the run loop holds the main actor and starves SwiftUI's tasks.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MYNOTCH_GLASS_CANARY"] != nil))
struct NotchTilesLayerCanaryTests {
    let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let red = (r: 255, g: 0, b: 0)

    struct Rig {
        let harness: RegistryHarness
        let model: NotchViewModel
        let hosting: NSHostingView<NotchRootView>
        let window: NSWindow
        let settings: SettingsStore
    }

    func rig(shape: NotchGlassShape, bubbles: Int = 0) async throws -> Rig {
        let harness = RegistryHarness([TabModule("a", order: 0), TabModule("b", order: 1)])
        await harness.registry.bootstrap()
        harness.settings.set(.liquidGlass, for: InterfaceSettings.look)
        harness.settings.set(shape, for: InterfaceSettings.glassShape)
        let theme = NotchTheme(settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { ["a", "b"] }, delays: { (.zero, .zero) })
        model.hasActivity = true
        harness.activities.set(
            LiveActivity(
                id: "p", leading: AnyView(Color(red: 1, green: 0, blue: 0).frame(width: 20, height: 12)),
                trailing: AnyView(Color(red: 0, green: 1, blue: 0).frame(width: 20, height: 12)), summary: "p"
            ),
            from: "m"
        )
        for index in 0..<bubbles {
            harness.activities.set(
                LiveActivity(id: "b\(index)", priority: .low, leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "b"),
                from: ModuleID(stringLiteral: "m\(index)")
            )
        }
        model.bubbleCount = CompactAccessories.bubbleCount(activities: harness.activities, geometry: geometry)
        let hosting = NSHostingView(
            rootView: NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
        )
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        try await Task.sleep(for: .milliseconds(600))
        return Rig(harness: harness, model: model, hosting: hosting, window: window, settings: harness.settings)
    }

    func layers(_ root: CALayer?, where match: (CALayer) -> Bool) -> [CALayer] {
        var found: [CALayer] = []
        func walk(_ layer: CALayer) {
            if match(layer) { found.append(layer) }
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        if let root { walk(root) }
        return found
    }

    func isColoured(_ layer: CALayer, _ colour: (r: Int, g: Int, b: Int)) -> Bool {
        guard let cg = layer.backgroundColor, let rgb = NSColor(cgColor: cg)?.usingColorSpace(.sRGB), rgb.alphaComponent > 0.5 else { return false }
        return Int(rgb.redComponent * 255) == colour.r && Int(rgb.greenComponent * 255) == colour.g && Int(rgb.blueComponent * 255) == colour.b
    }

    /// Whether `layer` is inside the layer SwiftUI makes for a view that carries glass: what is inside it is drawn above the glass
    /// (through a portal), and what is not is under the container's glass.
    func isInsideGlass(_ layer: CALayer) -> Bool {
        var current = layer.superlayer
        while let layer = current {
            if NSStringFromClass(type(of: layer)) == "SwiftUI.SDFLayer" { return true }
            current = layer.superlayer
        }
        return false
    }

    func elements(_ hosting: NSView) -> [CGRect] {
        layers(hosting.layer) { NSStringFromClass(type(of: $0)) == "CASDFElementLayer" }
            .map { layer in
                let presented = layer.presentation() ?? layer
                return presented.convert(presented.bounds, to: nil)
            }
            .sorted { $0.width > $1.width }
    }

    // MARK: the content is above the glass

    @Test func theCollapsedNotchsContentIsInsideTheGlassForBothShapes() async throws {
        for shape in NotchGlassShape.allCases {
            let rig = try await rig(shape: shape)
            defer { rig.window.contentView = nil }
            let probes = layers(rig.hosting.layer) { isColoured($0, red) }
            try #require(!probes.isEmpty, "\(shape): the strip's probe is in the tree")
            #expect(probes.allSatisfy(isInsideGlass), "\(shape): the strip is drawn above its glass")
        }
    }

    @Test func aToastsContentIsInsideTheGlassForBothShapes() async throws {
        for shape in NotchGlassShape.allCases {
            let rig = try await rig(shape: shape)
            defer { rig.window.contentView = nil }
            rig.model.showToast(AnyView(Color(red: 1, green: 0, blue: 0).frame(width: 40, height: 20)), duration: .seconds(60))
            try await Task.sleep(for: .milliseconds(500))
            let probes = layers(rig.hosting.layer) { isColoured($0, red) }
            try #require(!probes.isEmpty, "\(shape): the toast's probe is in the tree")
            #expect(probes.allSatisfy(isInsideGlass), "\(shape): the toast is drawn above its glass")
        }
    }

    // MARK: the tiles come out of the notch

    func sample(_ rig: Rig, _ change: () -> Void) async -> [(t: Double, elements: [CGRect])] {
        change()
        let start = Date()
        var samples: [(Double, [CGRect])] = []
        while Date().timeIntervalSince(start) < 1.2 {
            try? await Task.sleep(for: .milliseconds(4))
            samples.append((Date().timeIntervalSince(start) * 1000, elements(rig.hosting)))
        }
        return samples
    }

    @Test func theTilesSplitOutOfTheNotchFromTheFirstMomentAndMergeBackWithNoMomentWithoutGlass() async throws {
        let rig = try await rig(shape: .tiles)
        defer { rig.window.contentView = nil }
        let centre = geometry.panelSize.width / 2
        let rest = NotchTilesLayout.rest(collapsedSize: geometry.shapeSize(for: .compact), topRadius: 6, hasTabBar: true)
        let final = NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: 190), notchHeight: geometry.notchSize.height, topRadius: 8, tabCount: 2
        )

        func timeline(_ samples: [(t: Double, elements: [CGRect])]) -> String {
            var lines: [String] = []
            var lastPrinted = -100.0
            for sample in samples where sample.t - lastPrinted >= 45 {
                lastPrinted = sample.t
                lines.append("\(Int(sample.t))ms " + sample.elements.map { "\(Int($0.width))x\(Int($0.height))" }.joined(separator: ","))
            }
            return lines.joined(separator: " | ")
        }
        let opening = await sample(rig) { rig.model.open(tab: nil, onPurpose: false) }
        print("CANARY opening: \(timeline(opening))")
        #expect(opening.allSatisfy { !$0.elements.isEmpty }, "no sample of the opening without glass")
        // The glass is the rects of the tiles (an element is its shape grown by a few points each way).
        func near(_ rects: [CGRect], _ tile: NotchTilesLayout.Tile, slack: CGFloat) -> Bool {
            rects.contains { abs($0.width - tile.size.width) <= slack && abs($0.height - tile.size.height) <= slack }
        }
        let first = try #require(opening.first)
        print("CANARY first open sample \(Int(first.t)) ms: \(first.elements.map { "\(Int($0.width))x\(Int($0.height))" })  rest content \(rest.content.size)")
        let last = try #require(opening.last)
        print("CANARY last open sample: \(last.elements.map { "\(Int($0.width))x\(Int($0.height))@\(Int($0.minY))" })  final content \(final.content.size) tabBar \(String(describing: final.tabBar?.size))")
        #expect(near(last.elements, final.content, slack: 10), "the tile ends at its final rect")
        if let bar = final.tabBar { #expect(near(last.elements, bar, slack: 10), "and the capsule at its") }
        let widest = opening.flatMap(\.elements).map { abs($0.midX - centre) }.max() ?? 0
        // (A presentation layer is read while SwiftUI is still setting the frames of the others, so a sample can be a point or two off.)
        #expect(widest < 4, "centred the whole way: \(widest)")

        let closing = await sample(rig) { rig.model.close() }
        print("CANARY closing: \(timeline(closing))")
        #expect(closing.allSatisfy { !$0.elements.isEmpty }, "no sample of the closing without glass")
        let end = try #require(closing.last)
        print("CANARY last close sample: \(end.elements.map { "\(Int($0.width))x\(Int($0.height))" })")
        #expect(end.elements.allSatisfy { $0.width <= geometry.shapeSize(for: .compact).width + 12 }, "ends inside the collapsed notch")
        #expect((closing.flatMap(\.elements).map { abs($0.midX - centre) }.max() ?? 0) < 4)
    }

    @Test func theCollapsedNotchWithBubblesHasTheSlabsGlassAndTheTwoTilesUnderIt() async throws {
        let slab = try await rig(shape: .slab, bubbles: 2)
        defer { slab.window.contentView = nil }
        let tiles = try await rig(shape: .tiles, bubbles: 2)
        defer { tiles.window.contentView = nil }
        let slabCount = elements(slab.hosting).count
        let tilesCount = elements(tiles.hosting).count
        print("CANARY collapsed with 2 bubbles: slab \(slabCount) elements, tiles \(tilesCount)")
        #expect(slabCount == 3, "the notch and two bubbles")
        #expect(tilesCount == slabCount + 2, "and the capsule and the tile, inside the notch")
    }
}
