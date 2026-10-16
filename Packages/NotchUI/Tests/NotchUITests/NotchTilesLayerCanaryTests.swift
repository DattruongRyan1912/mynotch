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

    func rig(
        shape: NotchGlassShape, bubbles: Int = 0, clarity: NotchGlassClarity = .balanced, window appearance: NSAppearance.Name? = nil
    ) async throws -> Rig {
        let harness = RegistryHarness([TabModule("a", order: 0), TabModule("b", order: 1)])
        await harness.registry.bootstrap()
        harness.settings.set(.liquidGlass, for: InterfaceSettings.look)
        harness.settings.set(shape, for: InterfaceSettings.glassShape)
        harness.settings.set(clarity, for: InterfaceSettings.glassClarity)
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
        if let appearance { window.appearance = NSAppearance(named: appearance) }
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

    // MARK: the tiles come out of the notch and go back into it

    /// What the glass is, every few ms for 1.2 s after `change`: its elements, and in how many glass layers (SDF layers that hold any)
    /// they are. Shapes can only blend into one another inside one layer.
    func sample(_ rig: Rig, _ change: () -> Void) async -> [(t: Double, elements: [CGRect], layers: Int)] {
        change()
        let start = Date()
        var samples: [(Double, [CGRect], Int)] = []
        while Date().timeIntervalSince(start) < 1.2 {
            try? await Task.sleep(for: .milliseconds(4))
            samples.append((
                Date().timeIntervalSince(start) * 1000, elements(rig.hosting), glassLayers(rig.hosting).filter { !$0.elements.isEmpty }.count
            ))
        }
        return samples
    }

    /// The elements that are not the notch's own glass, which is the collapsed notch's shape (an element is its shape grown by 4 pt).
    func tileElements(_ elements: [CGRect]) -> [CGRect] {
        let notch = geometry.shapeSize(for: .compact)
        return elements.filter { !(abs($0.width - (notch.width + 8)) < 3 && abs($0.height - (notch.height + 8)) < 3) }
    }

    /// The elements of the tiles on screen: not the notch's own, and not a bubble's (32 pt).
    func tileGlass(_ hosting: NSView) -> [CGRect] { tileElements(elements(hosting)).filter { $0.width > 50 } }

    /// Polls `condition` every 20 ms, up to five seconds, with the main actor free while it sleeps: an assertion that something has gone
    /// waits for it to go, not for a stretch of the clock.
    func poll(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "gave up waiting: \(what)")
    }

    func opened(_ rig: Rig) async throws {
        rig.model.open(tab: nil, onPurpose: false)
        let width = NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: 190), topInset: geometry.openTopInset, topRadius: 8, tabCount: 2
        ).content.size.width
        try await poll("the tile open") { tileElements(elements(rig.hosting)).contains { abs($0.width - width) < 12 } }
    }

    func closed(_ rig: Rig) async throws {
        rig.model.close()
        try await poll("no glass but the notch's and the bubbles'") { tileGlass(rig.hosting).isEmpty }
    }

    func timeline(_ samples: [(t: Double, elements: [CGRect], layers: Int)]) -> String {
        var lines: [String] = []
        var lastPrinted = -100.0
        for sample in samples where sample.t - lastPrinted >= 45 {
            lastPrinted = sample.t
            lines.append("\(Int(sample.t))ms " + sample.elements.map { "\(Int($0.width))x\(Int($0.height))" }.joined(separator: ","))
        }
        return lines.joined(separator: " | ")
    }

    @Test func theTilesSplitOutOfTheNotchAndFlowBackIntoItInOneMotionWithNoMomentWithoutGlass() async throws {
        let rig = try await rig(shape: .tiles)
        defer { rig.window.contentView = nil }
        let centre = geometry.panelSize.width / 2
        let final = NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: 190), topInset: geometry.openTopInset, topRadius: 8, tabCount: 2
        )
        let pill = geometry.shapeSize(for: .compact)

        let opening = await sample(rig) { rig.model.open(tab: nil, onPurpose: false) }
        print("CANARY opening: \(timeline(opening))")
        #expect(opening.allSatisfy { !$0.elements.isEmpty }, "no sample of the opening without glass")
        #expect(opening.allSatisfy { $0.layers == 1 }, "the tiles are glass of one layer from the first frame")
        func near(_ rects: [CGRect], _ tile: NotchTilesLayout.Tile, slack: CGFloat) -> Bool {
            rects.contains { abs($0.width - tile.size.width) <= slack && abs($0.height - tile.size.height) <= slack }
        }
        let last = try #require(opening.last)
        #expect(last.elements.count == 2, "while it is open the glass is the capsule's and the tile's, with no pill over them: \(last.elements)")
        #expect(near(last.elements, final.content, slack: 10), "the tile ends at its final rect")
        if let bar = final.tabBar { #expect(near(last.elements, bar, slack: 10), "and the capsule at its") }
        #expect((opening.flatMap(\.elements).map { abs($0.midX - centre) }.max() ?? 0) < 4, "centred the whole way")

        let closing = await sample(rig) { rig.model.close() }
        print("CANARY closing: \(timeline(closing))")
        // One motion: there is glass at every moment, the notch's own (334 x 40 with the activity's strip) is there from the start of the
        // close at its size and is never put in again, and the tiles' and the notch's glass are in one layer, where the shapes blend.
        #expect(closing.allSatisfy { !$0.elements.isEmpty }, "no sample of the closing without glass")
        #expect(closing.allSatisfy { $0.layers == 1 }, "the tiles and the notch are glass of one layer all the way")
        func hasPill(_ sample: (t: Double, elements: [CGRect], layers: Int)) -> Bool {
            sample.elements.contains { abs($0.width - (pill.width + 8)) < 6 && abs($0.height - (pill.height + 8)) < 6 }
        }
        #expect(closing.filter { $0.t > 60 }.allSatisfy(hasPill), "the notch's glass is there the whole time the tiles go back")
        // The glass only merges: the number of elements never goes up again once the notch's own is in, and ends at the notch's alone.
        let counts = closing.map(\.elements.count)
        let peak = try #require(counts.max())
        #expect(peak == 3, "the notch's, the capsule's and the tile's: \(counts)")
        let afterPeak = counts[(try #require(counts.firstIndex(of: peak)))...]
        #expect(zip(afterPeak, afterPeak.dropFirst()).allSatisfy { $0 >= $1 }, "the elements only merge (never one put back in): \(counts)")
        #expect(counts.last == 1, "and one is left: \(counts)")
        // The tiles' glass is taken out when it is inside the notch's: nothing sticks out of the pill in the last sample that has the tiles.
        let lastWithTiles = try #require(closing.last { $0.elements.count >= 3 })
        #expect(
            lastWithTiles.elements.allSatisfy { $0.width <= pill.width + 8 + 6 && $0.height <= pill.height + 8 + 6 },
            "the tiles leave inside the pill: \(lastWithTiles.elements)"
        )
        // The content tile shrinks from the first moments, with no stretch at full size. Its glass element trails the layout by a few tens of
        // ms, so: it only goes down (to within 3 pt), is clearly down (40 pt) by 100 ms, and by 120 ms is under 90 % of its size. The
        // capsule is not followed: it widens on the way, and ends as wide as the tile.
        let tallest: ([CGRect]) -> CGFloat? = { $0.filter { $0.height > 60 }.max { $0.width < $1.width }?.width }
        let widths = closing.compactMap { sample in tallest(sample.elements).map { (sample.t, $0) } }
        let first = try #require(widths.first)
        #expect(first.0 < 60 && first.1 > final.content.size.width - 40, "the first sample sees the tile still at its size: \(first)")
        let at100 = try #require(widths.first { $0.0 >= 100 })
        #expect(at100.1 < first.1 - 40, "by \(Int(at100.0)) ms the tile is at \(at100.1) from \(first.1)")
        let at120 = try #require(widths.first { $0.0 >= 120 })
        #expect(at120.1 < final.content.size.width * 0.9, "by \(Int(at120.0)) ms the tile is at \(at120.1) of \(final.content.size.width)")
        var previous = CGFloat.infinity
        for (t, width) in widths {
            #expect(width <= previous + 3, "the tile does not grow while closing (\(Int(t)) ms)")
            previous = min(previous, width)
        }
        // At rest: the notch's glass alone, as in the slab.
        for sample in closing where sample.t > 900 {
            #expect(sample.elements.count == 1, "only the notch's glass is left at \(Int(sample.t)) ms: \(sample.elements)")
        }
        #expect((closing.flatMap(\.elements).map { abs($0.midX - centre) }.max() ?? 0) < 4)
    }

    /// The glass layers of the tree in the order they are drawn (a later one is above an earlier one), each with the frames of its elements.
    func glassLayers(_ hosting: NSView) -> [(layer: CALayer, elements: [CGRect])] {
        var found: [(CALayer, [CGRect])] = []
        func walk(_ layer: CALayer) {
            if NSStringFromClass(type(of: layer)) == "SwiftUI.SDFLayer" {
                let frames = layers(layer) { NSStringFromClass(type(of: $0)) == "CASDFElementLayer" }.map { element -> CGRect in
                    let presented = element.presentation() ?? element
                    return presented.convert(presented.bounds, to: nil)
                }
                found.append((layer, frames))
            }
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        if let root = hosting.layer { walk(root) }
        return found
    }

    /// Whether, inside the glass layer `glass`, what is drawn after every glass element is a portal (which is how the content of a glass
    /// view is shown above the glass: a copy of it, with the original hidden under the elements). The layers are in draw order.
    func contentIsPortalledAboveEveryElement(of glass: CALayer) -> Bool {
        var index = 0
        var lastElement = -1, firstPortal = Int.max
        func walk(_ layer: CALayer) {
            index += 1
            let name = NSStringFromClass(type(of: layer))
            if name == "CASDFElementLayer" { lastElement = index }
            if name.hasSuffix("SDFPortalLayer") { firstPortal = min(firstPortal, index) }
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        walk(glass)
        return lastElement > 0 && firstPortal != Int.max && firstPortal > lastElement
    }

    /// Runs `change` and for 1.2 s after it checks, every few ms, that the strip's text (the red probe) is drawn above all the glass: all
    /// the glass is in one layer (the notch's own, the tiles' and the bubbles' are shapes of one container, and that is also what lets them
    /// blend), whose content is portalled above every element of it; and should there be a second layer, no element of one drawn after
    /// the strip's is over it. Returns how many samples had the strip, and how many of them had glass under it (the tiles' or the toast's), which is what
    /// makes the check worth anything.
    func stripIsAboveTheGlass(_ rig: Rig, during change: () -> Void) async throws -> (checked: Int, underneath: Int) {
        change()
        let start = Date()
        var checked = 0, underneath = 0
        while Date().timeIntervalSince(start) < 1.2 {
            try await Task.sleep(for: .milliseconds(4))
            let probes = layers(rig.hosting.layer) { isColoured($0, red) }
            guard let probe = probes.first else { continue }
            let frame = probe.convert(probe.bounds, to: nil)
            let all = glassLayers(rig.hosting)
            var own = probe.superlayer
            while let layer = own, NSStringFromClass(type(of: layer)) != "SwiftUI.SDFLayer" { own = layer.superlayer }
            let ownLayer = try #require(own, "the strip is inside a glass layer")
            let index = try #require(all.firstIndex { $0.layer === ownLayer }, "the strip is inside a glass layer")
            checked += 1
            #expect(all.filter { !$0.elements.isEmpty }.count <= 1, "one glass layer: shapes that are in two do not blend and stack")
            #expect(contentIsPortalledAboveEveryElement(of: ownLayer), "the strip is shown above every element of its layer")
            for later in all[(index + 1)...] { #expect(!later.elements.contains { $0.intersects(frame) }, "glass above the strip: \(later.elements)") }
            // Under the strip: an element of an earlier layer, or a second one of its own layer that covers it.
            if all[..<index].contains(where: { $0.elements.contains { $0.intersects(frame) } })
                || all[index].elements.filter({ $0.intersects(frame) }).count > 1 {
                underneath += 1
            }
        }
        return (checked, underneath)
    }

    /// While the notch closes the tiles and the notch's glass are one layer, so the order of the views is not the text's: the strip is a
    /// portal above all the shapes of it. (In U3f they were two layers, with the tiles' drawn over the strip; two layers fail this.)
    @Test(arguments: [0, 2]) func theStripIsDrawnAboveEveryTilesGlassWhileTheNotchCloses(bubbles: Int) async throws {
        let rig = try await rig(shape: .tiles, bubbles: bubbles)
        defer { rig.window.contentView = nil }
        try await opened(rig)
        let result = try await stripIsAboveTheGlass(rig) { rig.model.close() }
        #expect(result.checked > 100, "the strip was there to check (\(result.checked) samples)")
        #expect(result.underneath > 0, "the tiles' glass was under the strip at some point")
    }

    /// A toast over the open tab covers it with the tiles as identity glass, and the notch goes from there to the collapsed pill while
    /// that fades: the same, with the toast's pill and the tiles' fading glass.
    @Test func theStripIsDrawnAboveTheCoveredTilesGlassWhenAToastGoesAndTheNotchCloses() async throws {
        let rig = try await rig(shape: .tiles)
        defer { rig.window.contentView = nil }
        try await opened(rig)
        rig.model.showToast(AnyView(Color.clear.frame(width: 40, height: 20)), duration: .seconds(60))
        try await poll("the toast") { rig.model.displayState == .toast }
        let result = try await stripIsAboveTheGlass(rig) { rig.model.close() }
        #expect(result.checked > 100, "the strip was there to check (\(result.checked) samples)")
    }

    @Test func noTileGlassOverlapsTheStripOnceTheNotchIsCollapsed() async throws {
        let rig = try await rig(shape: .tiles)
        defer { rig.window.contentView = nil }
        try await opened(rig)
        try await closed(rig)
        try await poll("every tile shape gone") { tileGlass(rig.hosting).isEmpty }
        let probes = layers(rig.hosting.layer) { isColoured($0, red) }
        try #require(!probes.isEmpty, "the strip is back")
        #expect(probes.allSatisfy(isInsideGlass))
        let strips = probes.map { $0.convert($0.bounds, to: nil) }
        let tiles = tileElements(elements(rig.hosting))
        #expect(tiles.isEmpty, "no glass but the notch's own: \(tiles)")
        for strip in strips { for tile in tiles { #expect(!tile.intersects(strip), "tile glass over the strip") } }
    }

    @Test func aToastOverATabThenGoingLeavesNoTileGlassBehindWithOrWithoutBubbles() async throws {
        for bubbles in [0, 2] {
            let rig = try await rig(shape: .tiles, bubbles: bubbles)
            defer { rig.window.contentView = nil }
            try await opened(rig)
            rig.model.showToast(AnyView(Color.clear.frame(width: 40, height: 20)), duration: .seconds(60))
            // In the toast the notch's own glass is the toast's pill, so once the tiles have faded it is the only glass over 50 pt wide.
            try await poll("the toast's pill alone") { rig.model.displayState == .toast && elements(rig.hosting).filter { $0.width > 50 }.count == 1 }
            try await closed(rig)
            try await poll("every tile shape gone") { tileGlass(rig.hosting).isEmpty }
            let count = elements(rig.hosting).count
            print("CANARY toast then close, \(bubbles) bubbles: \(elements(rig.hosting).map { "\(Int($0.width))x\(Int($0.height))" })")
            #expect(tileGlass(rig.hosting).isEmpty, "no tile glass left (\(bubbles) bubbles)")
            #expect(count == 1 + bubbles, "the notch's and the bubbles'")
        }
    }

    @Test func theCollapsedNotchHasExactlyTheSlabsGlassWithAndWithoutBubbles() async throws {
        for bubbles in [0, 2] {
            let slab = try await rig(shape: .slab, bubbles: bubbles)
            defer { slab.window.contentView = nil }
            let tiles = try await rig(shape: .tiles, bubbles: bubbles)
            defer { tiles.window.contentView = nil }
            // Straight away, and after a round of opening and closing.
            #expect(elements(tiles.hosting).count == elements(slab.hosting).count, "\(bubbles) bubbles, at the start")
            try await opened(tiles)
            try await closed(tiles)
            try await poll("every tile shape gone") { tileGlass(tiles.hosting).isEmpty }
            print("CANARY collapsed, \(bubbles) bubbles: slab \(elements(slab.hosting).count), tiles \(elements(tiles.hosting).count) after open and close")
            #expect(elements(tiles.hosting).count == elements(slab.hosting).count, "\(bubbles) bubbles, after open and close")
        }
    }

    // MARK: the clear glass has a material under it

    /// The blur radius of every material (a `gaussianBlur` backdrop) in the tree, and their opacities as drawn.
    func materials(_ hosting: NSView) -> [(radius: Double, opacity: Float)] {
        layers(hosting.layer) { layer in
            NSStringFromClass(type(of: layer)) == "CABackdropLayer"
                && (layer.filters ?? []).contains { ($0 as? NSObject)?.value(forKey: "name") as? String == "gaussianBlur" }
        }.map { layer in
            let filter = (layer.filters ?? []).compactMap { $0 as? NSObject }.first { $0.value(forKey: "name") as? String == "gaussianBlur" }
            return ((filter?.value(forKey: "inputRadius") as? Double) ?? -1, (layer.presentation() ?? layer).opacity)
        }
    }

    /// The glass of Trong vắt is `Glass.clear` with a material under each of its shapes, and Cân bằng has none. The numbers are the glass
    /// filter's (the regular glass's radius is 2 at a quarter resolution, the clear glass's 5 at a half; every material's is 60).
    @Test func trongVangHasAMaterialUnderEveryShapeAndCanBangNone() async throws {
        for shape in NotchGlassShape.allCases {
            for bubbles in [0, 2] {
                let balanced = try await rig(shape: shape, bubbles: bubbles, clarity: .balanced)
                defer { balanced.window.contentView = nil }
                #expect(materials(balanced.hosting).isEmpty, "\(shape), \(bubbles) bubbles: Cân bằng has no material")

                let clear = try await rig(shape: shape, bubbles: bubbles, clarity: .clear)
                defer { clear.window.contentView = nil }
                // The notch's own and each bubble's.
                #expect(materials(clear.hosting).map(\.radius) == Array(repeating: 60, count: 1 + bubbles), "\(shape), \(bubbles) bubbles, collapsed")
                if shape == .tiles {
                    clear.model.open(tab: nil, onPurpose: false)
                    // Open: the capsule's and the tile's (the notch's own view is not in the tree), and the bubbles' while they are.
                    try await poll("a material under each tile") { materials(clear.hosting).filter { $0.radius == 60 }.count >= 2 }
                    try await poll("the notch's own material gone") { materials(clear.hosting).count == 2 }
                    try await closed(clear)
                    try await poll("the tiles' materials gone") { materials(clear.hosting).count == 1 + bubbles }
                }
            }
        }
    }

    /// While the tiles merge into the notch their materials fade, so that two are not one over the other where they meet: by the time
    /// the tiles are inside the notch, theirs are gone, and the notch's own is whole from the first frame.
    @Test func theTilesMaterialsFadeAsTheyMergeIntoTheNotchsOwn() async throws {
        let rig = try await rig(shape: .tiles, clarity: .clear)
        defer { rig.window.contentView = nil }
        try await opened(rig)
        try await poll("a material under each tile") { materials(rig.hosting).count == 2 }
        let before = materials(rig.hosting).map(\.opacity)
        #expect(before.allSatisfy { $0 == 1 }, "whole while open: \(before)")
        rig.model.close()
        let start = Date()
        var peak = 0, faded = false
        var firstPill: Float?
        while Date().timeIntervalSince(start) < 1.2 {
            try await Task.sleep(for: .milliseconds(4))
            let now = materials(rig.hosting)
            peak = max(peak, now.count)
            if now.count == 3, firstPill == nil { firstPill = now.map(\.opacity).max() }
            if now.count == 3, now.map(\.opacity).min() ?? 1 < 0.3 { faded = true }
        }
        #expect(peak == 3, "the notch's and the two tiles' while they merge")
        #expect(faded, "a tile's material is mostly gone before the tile is taken out")
        #expect(materials(rig.hosting).count == 1, "the notch's own is left")
    }
}
