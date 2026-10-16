import AppKit
import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import NotchUI

@Observable private final class CanaryStripBox {
    var width: CGFloat = 330
}

private struct CanaryStrip: View {
    let box: CanaryStripBox
    var body: some View { Color.clear.notchStripWidth(box.width) }
}

private final class PillTabModule: FeatureModule {
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

/// The glass of the pill as the layer tree has it: where the glass elements are (the notch's own is its shape grown by 4 pt, a tile's or a bubble's is its shape) in the collapsed pill and
/// while it opens, that the strip's text is above the glass, and that the tiles start from the pill. Private layer classes and sampling the
/// run loop, so it is not part of the gate: `MYNOTCH_GLASS_CANARY=1 xcrun swift test --filter NotchPillCanaryTests` in `Packages/NotchUI`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MYNOTCH_GLASS_CANARY"] != nil))
struct NotchPillCanaryTests {
    let geometry = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))
    /// The same, opening as tiles (taller by their chrome).
    let tilesGeometry = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill, opensAsTiles: true))
    let gap = NotchGeometry.pillTopGap
    let red = (r: 255, g: 0, b: 0)

    struct Rig {
        let harness: RegistryHarness
        let theme: NotchTheme
        let model: NotchViewModel
        let hosting: NSHostingView<NotchRootView>
        let window: NSWindow

        /// What the window controller does when the style changes: a new root view of the new geometry, and a panel of the new size.
        func show(_ geometry: NotchGeometry) {
            hosting.rootView = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
            window.setContentSize(geometry.panelSize)
            hosting.frame = CGRect(origin: .zero, size: geometry.panelSize)
        }
    }

    func rig(
        shape: NotchGlassShape, clarity: NotchGlassClarity = .balanced, bubbles: Int = 0, style: VirtualNotchStyle = .pill,
        screen: ScreenDescriptor = NotchGeometryTests.external
    ) async throws -> Rig {
        let geometry = NotchGeometry(screen: screen, config: NotchLayoutConfig(virtualNotchStyle: style, opensAsTiles: shape == .tiles))
        let harness = RegistryHarness([PillTabModule("a", order: 0), PillTabModule("b", order: 1)])
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
        window.contentView = hosting
        try await Task.sleep(for: .milliseconds(600))
        return Rig(harness: harness, theme: theme, model: model, hosting: hosting, window: window)
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

    func isInsideGlass(_ layer: CALayer) -> Bool {
        var current = layer.superlayer
        while let layer = current {
            if NSStringFromClass(type(of: layer)) == "SwiftUI.SDFLayer" { return true }
            current = layer.superlayer
        }
        return false
    }

    /// The glass elements, as rects from the panel's top left (the layers' y grows up, whatever `isFlipped` of the hosting view says).
    func elements(_ hosting: NSView) -> [CGRect] {
        layers(hosting.layer) { NSStringFromClass(type(of: $0)) == "CASDFElementLayer" }
            .map { layer in
                let presented = layer.presentation() ?? layer
                let rect = presented.convert(presented.bounds, to: nil)
                return CGRect(x: rect.minX, y: hosting.bounds.height - rect.maxY, width: rect.width, height: rect.height)
            }
            .sorted { $0.width > $1.width }
    }

    func poll(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition(), "gave up waiting: \(what)")
    }

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

    /// How far from the panel's middle the centre of any element wider than `width` is, in any sample.
    func worstCentreOffset(_ samples: [(t: Double, elements: [CGRect])], wider width: CGFloat) -> CGFloat {
        let middle = geometry.panelSize.width / 2
        var worst: CGFloat = 0
        for sample in samples {
            for rect in sample.elements where rect.width > width { worst = max(worst, abs(rect.midX - middle)) }
        }
        return worst
    }

    /// Every 48 ms or so: the time and each element as "left,top widthxheight".
    func timeline(_ samples: [(t: Double, elements: [CGRect])]) -> String {
        var lines: [String] = []
        var last = -100.0
        for sample in samples where sample.t - last >= 48 {
            last = sample.t
            let rects = sample.elements.map { rect in
                "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
            }
            lines.append("\(Int(sample.t))ms " + rects.joined(separator: ", "))
        }
        return lines.joined(separator: " | ")
    }

    // MARK: collapsed

    @Test func theCollapsedPillsGlassIsThePillsShapeFloatingTheGapBelowTheTopEdge() async throws {
        for shape in NotchGlassShape.allCases {
            let rig = try await rig(shape: shape)
            defer { rig.window.contentView = nil }
            let compact = geometry.shapeSize(for: .compact)
            let notch = try #require(elements(rig.hosting).first { $0.width > 100 }, "\(shape): the pill's glass")
            #expect(abs(notch.width - (compact.width + 8)) < 3 && abs(notch.height - (compact.height + 8)) < 3, "\(shape): \(notch)")
            #expect(abs(notch.midX - geometry.panelSize.width / 2) < 1, "\(shape): centred \(notch)")
            #expect(abs(notch.minY - (gap - 4)) < 2, "\(shape): the gap below the edge, less the element's 4 pt (\(notch))")
            let probes = layers(rig.hosting.layer) {
                guard let cg = $0.backgroundColor, let rgb = NSColor(cgColor: cg)?.usingColorSpace(.sRGB), rgb.alphaComponent > 0.5 else { return false }
                return Int(rgb.redComponent * 255) == 255 && Int(rgb.greenComponent * 255) == 0
            }
            try #require(!probes.isEmpty, "\(shape): the strip's probe is in the tree")
            #expect(probes.allSatisfy(isInsideGlass), "\(shape): the strip is drawn above its glass")
        }
    }

    @Test func theBubblesAreGlassBesideThePillAtTheSameHeight() async throws {
        let rig = try await rig(shape: .slab, bubbles: 2)
        defer { rig.window.contentView = nil }
        let bubbles = elements(rig.hosting).filter { $0.width < 60 }
        try #require(bubbles.count == 2, "two bubbles: \(bubbles)")
        let compact = geometry.shapeSize(for: .compact)
        let notch = try #require(elements(rig.hosting).first { $0.width > 100 })
        for bubble in bubbles {
            #expect(abs(bubble.midY - notch.midY) < 2, "centred on the pill: \(bubble) \(notch)")
            #expect(abs(bubble.minY - gap) < 1.5 && abs(bubble.height - geometry.bubbleDiameter) < 1.5, "as tall as the pill's body, from its top")
        }
        #expect(abs(bubbles.map(\.minX).min()! - (geometry.panelSize.width / 2 + compact.width / 2 + NotchGeometry.bubbleGap)) < 1.5, "6 pt from the pill's end (a bubble's element is its shape)")
    }

    // MARK: open

    @Test func theSlabGrowsFromThePillsCentreToTheOpenRectWithTheSameTopGap() async throws {
        for clarity in NotchGlassClarity.allCases {
            let rig = try await rig(shape: .slab, clarity: clarity)
            defer { rig.window.contentView = nil }
            let open = geometry.shapeSize(for: .open(nil), contentHeight: 190)
            let opening = await sample(rig) { rig.model.open(tab: nil, onPurpose: false) }
            print("CANARY pill slab \(clarity): \(timeline(opening))")
            #expect(opening.allSatisfy { !$0.elements.isEmpty }, "\(clarity): no sample without glass")
            #expect(worstCentreOffset(opening, wider: 100) < 4, "\(clarity): centred")
            let last = try #require(opening.last?.elements.first)
            #expect(abs(last.width - (open.width + 8)) < 6 && abs(last.height - (open.height + 8)) < 6, "\(clarity): \(last)")
            #expect(abs(last.minY - (gap - 4)) < 3, "\(clarity): the top stays where it was: \(last)")
            let tops = opening.flatMap(\.elements).filter { $0.width > 100 }.map(\.minY)
            #expect((tops.max() ?? 0) - (tops.min() ?? 0) < 6, "\(clarity): the top does not move while it grows")
        }
    }

    @Test func theTilesStartFromThePillAndEndWhereTheTabPagePutsThemWithNoMomentWithoutGlass() async throws {
        for clarity in NotchGlassClarity.allCases {
            let rig = try await rig(shape: .tiles, clarity: clarity)
            defer { rig.window.contentView = nil }
            let pill = geometry.shapeSize(for: .compact)
            let final = NotchTilesLayout.open(
                shapeSize: tilesGeometry.shapeSize(for: .open(nil), contentHeight: 190, tabCount: 2), topInset: tilesGeometry.openTopInset,
                topRadius: 0, tabCount: 2
            )
            let opening = await sample(rig) { rig.model.open(tab: nil, onPurpose: false) }
            print("CANARY pill tiles \(clarity): \(timeline(opening))")
            #expect(opening.allSatisfy { !$0.elements.isEmpty }, "\(clarity): no sample without glass")
            let first = try #require(opening.first)
            // The first sample has the tiles at the pill's own rect (a little grown, as the spring starts) and not at their final ones.
            #expect(first.elements.contains { abs($0.width - pill.width) < 40 && $0.height < pill.height + 20 }, "\(clarity): \(first.elements)")
            #expect(worstCentreOffset(opening, wider: 60) < 4, "\(clarity): centred")
            let last = try #require(opening.last)
            #expect(last.elements.contains { abs($0.width - final.content.size.width) < 3 && abs($0.height - final.content.size.height) < 3 }, "\(clarity): the tile ends at its rect: \(last.elements)")
            let topOfTile = try #require(last.elements.first { $0.width > 300 }).minY
            #expect(abs(topOfTile - (gap + final.content.top)) < 3, "\(clarity): the gap and the tab page's top: \(topOfTile)")
        }
    }

    @Test func theTilesFlowBackIntoThePillInsideItAndLeaveOnlyItsGlass() async throws {
        let rig = try await rig(shape: .tiles)
        defer { rig.window.contentView = nil }
        let pill = geometry.shapeSize(for: .compact)
        rig.model.open(tab: nil, onPurpose: false)
        try await poll("the tile open") { elements(rig.hosting).contains { $0.width > 500 } }
        try await Task.sleep(for: .milliseconds(600))
        let closing = await sample(rig) { rig.model.close() }
        print("CANARY pill closing: \(timeline(closing))")
        #expect(closing.allSatisfy { !$0.elements.isEmpty }, "no sample without glass")
        #expect(worstCentreOffset(closing, wider: 60) < 4, "centred")
        // The notch's own glass (the pill's shape, grown by 4) is there from the first moments of the close, with the tiles coming back
        // into it.
        let isPill: (CGRect) -> Bool = { abs($0.width - (pill.width + 8)) < 6 && abs($0.height - (pill.height + 8)) < 6 }
        #expect(closing.filter { $0.t > 60 }.allSatisfy { $0.elements.contains(where: isPill) }, "the pill's glass is there the whole time")
        // Nothing of a tile sticks out of the pill by the time the tiles are taken out, and a tile that is back sits inside the pill's rect.
        let lastWithTiles = try #require(closing.last { $0.elements.count >= 3 })
        let outside = lastWithTiles.elements.filter { $0.width > pill.width + 8 + 6 || $0.height > pill.height + 8 + 6 }
        #expect(outside.isEmpty, "the tiles leave inside the pill: \(lastWithTiles.elements)")
        for sample in closing where sample.t > 900 {
            #expect(sample.elements.count == 1, "only the pill's glass is left at \(Int(sample.t)) ms: \(sample.elements)")
        }
    }

    // MARK: switching the style

    @Test(arguments: NotchGlassShape.allCases, [false, true])
    func switchingTheStyleSpringsTheGlassAndNeverJumps(shape: NotchGlassShape, opened: Bool) async throws {
        let rig = try await rig(shape: shape, style: .notch)
        defer { rig.window.contentView = nil }
        if opened {
            rig.model.open(tab: nil, onPurpose: false)
            try await poll("open") { elements(rig.hosting).contains { $0.width > 300 } }
            try await Task.sleep(for: .milliseconds(700))
        }
        let before = elements(rig.hosting)
        let pill = shape == .tiles ? tilesGeometry : geometry
        let toPill = await sample(rig) { rig.show(pill) }
        print("CANARY style notch -> pill (\(shape), opened \(opened)): \(timeline(toPill))")
        #expect(toPill.allSatisfy { !$0.elements.isEmpty }, "no sample without glass")
        // A spring passes through values between the two, not from one to the other: the biggest element's top and width take several
        // different values on the way.
        let tops = Set(toPill.compactMap { $0.elements.first }.map { Int($0.minY.rounded()) })
        #expect(tops.count >= 3, "the top moves through \(tops.sorted()), a spring and not a jump (from \(before.first.map(\.minY) ?? -1))")
        let settled = try #require(toPill.last?.elements.first)
        // The notch's own glass is its shape grown by 4 pt; the open tiles' (the biggest elements, with tiles) are their shapes.
        let tile = NotchTilesLayout.open(
            shapeSize: tilesGeometry.shapeSize(for: .open(nil), contentHeight: 190, tabCount: 2), topInset: tilesGeometry.openTopInset,
            topRadius: 0, tabCount: 2
        ).content
        let expectedTop = shape == .tiles && opened ? gap + tile.top : gap - 4
        #expect(abs(settled.minY - expectedTop) < 3, "and ends a gap below where it was: \(settled)")
        // And the notch: back to where it was.
        let toNotch = await sample(rig) { rig.show(NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(opensAsTiles: shape == .tiles))) }
        let back = try #require(toNotch.last?.elements.first)
        #expect(abs(back.minY - (before.first?.minY ?? 0)) < 3 && abs(back.width - (before.first?.width ?? 0)) < 3, "\(back) against \(before.first.map { "\($0)" } ?? "-")")
    }

    // MARK: a display without a cutout opens from the top, in both styles

    @Test(arguments: VirtualNotchStyle.allCases, NotchGlassShape.allCases)
    func theOpenNotchGrowsInPlaceFromTheCollapsedShapeWithItsTopFixedAndTheTabPageNearTheTop(style: VirtualNotchStyle, shape: NotchGlassShape) async throws {
        let geometry = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: style, opensAsTiles: shape == .tiles))
        let rig = try await rig(shape: shape, style: style)
        defer { rig.window.contentView = nil }
        let final = NotchTilesLayout.open(
            shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: 190, tabCount: 2), topInset: geometry.openTopInset,
            topRadius: geometry.cornerRadii(for: .open(nil)).top, tabCount: 2
        )
        let opening = await sample(rig) { rig.model.open(tab: nil, onPurpose: false) }
        print("CANARY open from the top (\(style), \(shape)): \(timeline(opening))")
        #expect(opening.allSatisfy { !$0.elements.isEmpty }, "no sample without glass")
        #expect(worstCentreOffset(opening, wider: 60) < 4, "grows about its centre")
        let last = try #require(opening.last)
        if shape == .slab {
            let open = geometry.shapeSize(for: .open(nil), contentHeight: 190)
            let notch = try #require(last.elements.first)
            #expect(abs(notch.width - (open.width + 8)) < 6 && abs(notch.height - (open.height + 8)) < 6, "\(notch)")
            // The open shape is the padding and the content tall, not the cutout's 25 pt and the content.
            #expect(abs(open.height - (14 + 190)) < 0.01)
            let tops = opening.flatMap(\.elements).filter { $0.width > 100 }.map(\.minY)
            #expect((tops.max() ?? 0) - (tops.min() ?? 0) < 6, "its top stays where the collapsed one's is, while it grows: \(tops.min() ?? 0) to \(tops.max() ?? 0)")
            #expect(abs(notch.minY - (geometry.topGap - 4)) < 3, "\(notch)")
        } else {
            let tile = try #require(last.elements.first { $0.width > 300 })
            #expect(abs(tile.minY - (geometry.topGap + final.content.top)) < 3, "the tile: \(tile)")
            let capsule = try #require(last.elements.first { $0.width < 150 && $0.height > 20 })
            #expect(abs(capsule.minY - (geometry.topGap + (final.tabBar?.top ?? 0))) < 3, "the capsule is the padding under the top: \(capsule)")
            let first = try #require(opening.first)
            let body = geometry.shapeSize(for: .compact)
            #expect(first.elements.contains { abs($0.width - body.width) < 40 && $0.height < body.height + 20 && abs($0.minY - geometry.topGap) < 6 }, "the tiles start as the collapsed notch: \(first.elements)")
        }
        let closing = await sample(rig) { rig.model.close() }
        #expect(closing.allSatisfy { !$0.elements.isEmpty }, "close mirrors open: no sample without glass")
        #expect(worstCentreOffset(closing, wider: 60) < 4)
        let rest = try #require(closing.last?.elements)
        #expect(rest.count == 1 && abs(rest[0].width - (geometry.shapeSize(for: .compact).width + 8)) < 6, "back to the collapsed notch's glass alone: \(rest)")
    }

    @Test(arguments: NotchGlassShape.allCases)
    func theNotchMovingFromADisplayWithACutoutToOneWithoutSpringsAndNeverJumps(shape: NotchGlassShape) async throws {
        let rig = try await rig(shape: shape, style: .notch, screen: NotchGeometryTests.macBook14)
        defer { rig.window.contentView = nil }
        rig.model.open(tab: nil, onPurpose: false)
        try await poll("open") { elements(rig.hosting).contains { $0.width > 300 } }
        try await Task.sleep(for: .milliseconds(700))
        let before = elements(rig.hosting)
        let external = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill, opensAsTiles: shape == .tiles))
        let moving = await sample(rig) { rig.show(external) }
        print("CANARY MacBook -> external (\(shape)): \(timeline(moving))")
        #expect(moving.allSatisfy { !$0.elements.isEmpty }, "no sample without glass")
        // The glass passes through values between the two, with the band going: the slab's height shrinks, and the tiles slide up, through
        // several values and not from one to the other.
        let path = Set(moving.compactMap { $0.elements.first }.map { Int((shape == .slab ? $0.height : $0.minY).rounded()) })
        #expect(path.count >= 3, "goes through \(path.sorted()), a spring and not a jump (from \(before.first.map { "\($0)" } ?? "-"))")
        let first = try #require(before.first)
        let settled = try #require(moving.last?.elements.first)
        #expect(abs(settled.height - (shape == .slab ? first.height - 18 : first.height)) < 3, "18 pt shorter with the slab, the same tile with tiles: \(first) -> \(settled)")
        #expect(abs(settled.minY - (shape == .slab ? first.minY + 5 : first.minY - 13)) < 3, "the slab's top is the pill's gap lower (a MacBook's sits at the edge) and the tile 18 pt higher less the gap: \(first) -> \(settled)")
    }

    // MARK: a strip that wants a wider notch

    @Test(arguments: VirtualNotchStyle.allCases, NotchGlassShape.allCases)
    func theCollapsedNotchWidensForItsStripWithTheSpringAboutItsCentreAndItsBubblesGoWithIt(
        style: VirtualNotchStyle, shape: NotchGlassShape
    ) async throws {
        // The two clarities are shared out between the shapes.
        let clarity: NotchGlassClarity = shape == .tiles ? .clear : .balanced
        let geometry = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: style, opensAsTiles: shape == .tiles))
        let harness = RegistryHarness([PillTabModule("a", order: 0), PillTabModule("b", order: 1)])
        await harness.registry.bootstrap()
        harness.settings.set(.liquidGlass, for: InterfaceSettings.look)
        harness.settings.set(shape, for: InterfaceSettings.glassShape)
        harness.settings.set(clarity, for: InterfaceSettings.glassClarity)
        let theme = NotchTheme(settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { ["a", "b"] }, delays: { (.zero, .zero) })
        model.hasActivity = true
        let box = CanaryStripBox()
        harness.activities.set(
            LiveActivity(
                id: "lyrics", leading: AnyView(Color.clear.frame(width: 16, height: 16)), trailing: AnyView(Color.clear.frame(width: 16, height: 12)),
                bottom: AnyView(CanaryStrip(box: box)), bottomHeight: 36, summary: "lyrics"
            ),
            from: "media"
        )
        harness.activities.set(
            LiveActivity(id: "bubble", priority: .low, leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "b"), from: "other"
        )
        model.bubbleCount = CompactAccessories.bubbleCount(activities: harness.activities, geometry: geometry)
        let hosting = NSHostingView(
            rootView: NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
        )
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await Task.sleep(for: .milliseconds(700))
        let rig = Rig(harness: harness, theme: theme, model: model, hosting: hosting, window: window)
        let before = geometry.compactWidth(stripWidth: 330)
        let after = geometry.compactWidth(stripWidth: 500)
        #expect(after > before)
        let widening = await sample(rig) { box.width = 500 }
        print("CANARY strip widens (\(style), \(shape), \(clarity)): \(timeline(widening))")
        #expect(widening.allSatisfy { !$0.elements.isEmpty }, "no sample without glass")
        let widths = Set(widening.compactMap { $0.elements.first { $0.width > 200 } }.map { Int($0.width.rounded()) })
        #expect(widths.count >= 4, "the notch goes through \(widths.sorted()): a spring, not a jump")
        #expect(worstCentreOffset(widening, wider: 200) < 4, "about its centre")
        let settled = try #require(widening.last?.elements.first { $0.width > 200 })
        #expect(abs(settled.width - (after + 8)) < 6, "ends as wide as the strip wants, the element's 4 pt each side: \(settled.width) against \(after + 8)")
        // The bubble is beside the pill's new end.
        let bubble = try #require(widening.last?.elements.first { $0.width < 60 })
        let end = geometry.panelSize.width / 2 + after / 2 - geometry.cornerRadii(for: .compact).top
        #expect(abs(bubble.minX - (end + NotchGeometry.bubbleGap)) < 3, "beside the pill with the same gap: \(bubble) after \(end)")
        // Opening the list (hovering a bubble) leaves the notch as wide as its strip made it, so the bubble stays under the pointer.
        model.showList()
        try await poll("the list is open") { model.isListOpen }
        let listOpen = await sample(rig) {}
        let widthsWithList = listOpen.compactMap { $0.elements.first { $0.width > 200 } }.map(\.width)
        #expect(!widthsWithList.isEmpty && widthsWithList.allSatisfy { abs($0 - (after + 8)) < 6 }, "the notch keeps its width with the list open: \(Set(widthsWithList.map { Int($0) }).sorted())")
        let bubbleWithList = try #require(listOpen.last?.elements.first { $0.width < 60 && $0.height < 60 })
        #expect(abs(bubbleWithList.minX - bubble.minX) < 3, "and the bubble does not move: \(bubble.minX) -> \(bubbleWithList.minX)")
        // (No bubble to hover: the list goes, as it does when the other activity ends.)
        model.bubbleCount = 0
        try await poll("the list is closed") { !model.isListOpen }
        model.bubbleCount = 1
        try await Task.sleep(for: .milliseconds(500))
        // And it narrows back with the spring when the strip asks for much less.
        let narrowing = await sample(rig) { box.width = 330 }
        let back = try #require(narrowing.last?.elements.first { $0.width > 200 })
        #expect(abs(back.width - (before + 8)) < 6, "\(back.width) against \(before + 8)")
    }
}
