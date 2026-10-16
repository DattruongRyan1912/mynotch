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
        shape: NotchGlassShape, bubbles: Int = 0, clarity: NotchGlassClarity = .balanced, recipe: NotchClearRecipeSwitch = .default,
        window appearance: NSAppearance.Name? = nil
    ) async throws -> Rig {
        let harness = RegistryHarness([TabModule("a", order: 0), TabModule("b", order: 1)])
        await harness.registry.bootstrap()
        harness.settings.set(.liquidGlass, for: InterfaceSettings.look)
        harness.settings.set(shape, for: InterfaceSettings.glassShape)
        harness.settings.set(clarity, for: InterfaceSettings.glassClarity)
        let theme = NotchTheme(
            settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter(), lookState: nil,
            clearRecipe: recipe
        )
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
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: 190), notchHeight: geometry.notchSize.height, topRadius: 8, tabCount: 2
        ).content.size.width
        try await poll("the tile open") { tileElements(elements(rig.hosting)).contains { abs($0.width - width) < 12 } }
    }

    func closed(_ rig: Rig) async throws {
        rig.model.close()
        try await poll("no glass but the notch's and the bubbles'") { tileGlass(rig.hosting).isEmpty }
    }

    func timeline(_ samples: [(t: Double, elements: [CGRect])]) -> String {
        var lines: [String] = []
        var lastPrinted = -100.0
        for sample in samples where sample.t - lastPrinted >= 45 {
            lastPrinted = sample.t
            lines.append("\(Int(sample.t))ms " + sample.elements.map { "\(Int($0.width))x\(Int($0.height))" }.joined(separator: ","))
        }
        return lines.joined(separator: " | ")
    }

    @Test func theTilesSplitOutOfTheNotchAndMergeBackWithNoMomentWithoutGlassAndNoGlassOfTheirsLeftAtRest() async throws {
        let rig = try await rig(shape: .tiles)
        defer { rig.window.contentView = nil }
        let centre = geometry.panelSize.width / 2
        let final = NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: 190), notchHeight: geometry.notchSize.height, topRadius: 8, tabCount: 2
        )

        let opening = await sample(rig) { rig.model.open(tab: nil, onPurpose: false) }
        print("CANARY opening: \(timeline(opening))")
        #expect(opening.allSatisfy { !$0.elements.isEmpty }, "no sample of the opening without glass")
        func near(_ rects: [CGRect], _ tile: NotchTilesLayout.Tile, slack: CGFloat) -> Bool {
            rects.contains { abs($0.width - tile.size.width) <= slack && abs($0.height - tile.size.height) <= slack }
        }
        let last = try #require(opening.last)
        #expect(near(last.elements, final.content, slack: 10), "the tile ends at its final rect")
        if let bar = final.tabBar { #expect(near(last.elements, bar, slack: 10), "and the capsule at its") }
        #expect((opening.flatMap(\.elements).map { abs($0.midX - centre) }.max() ?? 0) < 4, "centred the whole way")

        let closing = await sample(rig) { rig.model.close() }
        print("CANARY closing: \(timeline(closing))")
        #expect(closing.allSatisfy { !$0.elements.isEmpty }, "no sample of the closing without glass")
        // The content tile shrinks from the first moments, with no stretch at full size. Its glass element trails the layout by a few tens of
        // ms (that is the element's, not a spring's), so: it only goes down (to within 3 pt), is clearly down (40 pt) by 80 ms, and by
        // 130 ms is under 90 % of its size. The capsule is not followed: it widens on the way, and ends as wide as the tile.
        let tallest: ([CGRect]) -> CGFloat? = { tileElements($0).filter { $0.height > 60 }.max { $0.width < $1.width }?.width }
        let widths = closing.compactMap { sample in tallest(sample.elements).map { (sample.t, $0) } }
        let first = try #require(widths.first)
        #expect(first.0 < 60 && first.1 > final.content.size.width - 40, "the first sample sees the tile still at its size: \(first)")
        let at80 = try #require(widths.first { $0.0 >= 80 })
        #expect(at80.1 < first.1 - 40, "by \(Int(at80.0)) ms the tile is at \(at80.1) from \(first.1)")
        let at130 = try #require(widths.first { $0.0 >= 130 })
        #expect(at130.1 < final.content.size.width * 0.9, "by \(Int(at130.0)) ms the tile is at \(at130.1) of \(final.content.size.width)")
        var previous = CGFloat.infinity
        for (t, width) in widths {
            #expect(width <= previous + 3, "the tile does not grow while closing (\(Int(t)) ms)")
            previous = min(previous, width)
        }
        // Once it is back, its glass is dropped on the way and what is left fades out (the window server takes about 0.6 s over that,
        // whatever it is told): after 800 ms none of the tiles' is left, only the notch's own, as in the slab.
        for sample in closing where sample.t > 800 {
            #expect(tileElements(sample.elements).isEmpty, "no tile glass left at \(Int(sample.t)) ms: \(sample.elements)")
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

    /// While the notch closes, the strip's text is in the glass layer that is drawn last: no glass of a tile is ever above it, however
    /// much of the glass is still under it (the tiles are the size of the notch's body when they go).
    @Test func theStripIsDrawnAboveEveryTilesGlassWhileTheNotchCloses() async throws {
        let rig = try await rig(shape: .tiles)
        defer { rig.window.contentView = nil }
        try await opened(rig)
        rig.model.close()
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
            let index = try #require(all.firstIndex { $0.layer === own }, "the strip is inside a glass layer")
            checked += 1
            for later in all[(index + 1)...] { #expect(!later.elements.contains { $0.intersects(frame) }, "glass above the strip: \(later.elements)") }
            if all[..<index].contains(where: { $0.elements.contains { $0.intersects(frame) } }) { underneath += 1 }
        }
        #expect(checked > 100, "the strip was there to check (\(checked) samples)")
        // Not vacuous: for a while the tiles' glass really is under the strip (it is the size of the notch's body, which holds the strip).
        #expect(underneath > 0, "the tiles' glass was under the strip at some point")
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

    // MARK: the candidates for the clear glass (U3g, temporary) reach the glass layers

    /// What the window server is given for the glass: the `glassBackground` filter's blur radius and face colour matrix (the white and
    /// black points the blurred backdrop is mapped to), whether a tint fill layer is there, and the blur radius of every material
    /// backdrop (a `gaussianBlur` filter) under it.
    func glassFacts(_ hosting: NSView) -> (blur: Double, white: Double, black: Double, fills: Int, materials: [Double]) {
        var facts = (blur: -1.0, white: -1.0, black: -1.0, fills: 0, materials: [Double]())
        _ = layers(hosting.layer) { layer in
            let name = NSStringFromClass(type(of: layer))
            if name == "CABackdropLayer" {
                for case let filter as NSObject in layer.filters ?? [] {
                    switch filter.value(forKey: "name") as? String {
                    case "glassBackground":
                        facts.blur = (filter.value(forKey: "inputBlurRadius") as? Double) ?? -1
                        facts.white = (filter.value(forKey: "inputFaceColorMatrixWhite") as? Double) ?? -1
                        facts.black = (filter.value(forKey: "inputFaceColorMatrixBlack") as? Double) ?? -1
                    case "gaussianBlur": facts.materials.append((filter.value(forKey: "inputRadius") as? Double) ?? -1)
                    default: break
                    }
                }
            }
            if name == "CASDFLayer", let effect = layer.value(forKey: "effect") as? NSObject, NSStringFromClass(type(of: effect)) == "CASDFFillEffect" {
                facts.fills += 1
            }
            return false
        }
        return facts
    }

    @Test func eachCandidateForTheClearGlassReachesTheGlassTheWayItIsMeant() async throws {
        func facts(_ clarity: NotchGlassClarity, _ recipe: NotchClearRecipe, tint: Double = 0.12, shape: NotchGlassShape = .slab) async throws -> (blur: Double, white: Double, black: Double, fills: Int, materials: [Double]) {
            let rig = try await rig(
                shape: shape, clarity: clarity, recipe: NotchClearRecipeSwitch(recipe: recipe, tint: tint), window: .darkAqua
            )
            defer { rig.window.contentView = nil }
            if shape == .tiles {
                rig.model.open(tab: nil, onPurpose: false)
                try await poll("the tiles, with a material under each and the notch's own gone") { glassFacts(rig.hosting).materials.count == 2 }
            }
            let found = glassFacts(rig.hosting)
            print("CANARY recipe \(clarity) \(recipe) \(shape): blur \(found.blur), white/black \(found.white)/\(found.black), fills \(found.fills), materials \(found.materials)")
            return found
        }
        let balanced = try await facts(.balanced, .regularLight)
        let raw = try await facts(.clear, .raw)
        let light = try await facts(.clear, .regularLight)
        let tint = try await facts(.clear, .regularTint)
        let over = try await facts(.clear, .clearOverBlur)
        let regularOver = try await facts(.clear, .regularOverBlur)
        // The numbers depend on the size of the glass (the open notch's are about twice these), so they are compared, not fixed. Balanced
        // is regular glass in a dark window whatever recipe is set; today's clear glass keeps more contrast (a lower black point and a
        // higher white point) and has a larger nominal blur radius at twice the resolution.
        #expect(balanced.fills == 0 && balanced.materials.isEmpty && raw.fills == 0 && raw.materials.isEmpty)
        #expect(raw.black < balanced.black && raw.white > balanced.white && raw.blur > balanced.blur)
        // Forced light reaches the glass: the same blur, a lighter map (the window is dark).
        #expect(light.blur == balanced.blur && light.black > balanced.black && light.white > balanced.white && light.materials.isEmpty)
        // The tint is a fill on top of the regular glass's own map.
        #expect(tint.blur == balanced.blur && tint.black == balanced.black && tint.white == balanced.white && tint.fills > balanced.fills)
        // The blur recipes put a material (radius 60) under the glass and keep the glass of their own kind.
        #expect(over.materials == [60] && over.blur == raw.blur && over.black == raw.black && over.white == raw.white)
        #expect(regularOver.materials == [60] && regularOver.blur == balanced.blur && regularOver.black == balanced.black)
        // The tiles carry it too: one material under each tile's glass.
        let tiles = try await facts(.clear, .clearOverBlur, shape: .tiles)
        #expect(tiles.materials.count == 2 && tiles.materials.allSatisfy { $0 == 60 }, "\(tiles.materials)")
    }
}
