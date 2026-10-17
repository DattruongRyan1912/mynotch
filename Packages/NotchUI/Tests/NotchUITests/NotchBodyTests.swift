import AppKit
import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import NotchUI

/// A live activity may draw across the whole top row of the collapsed notch (`LiveActivity.body`): at the notch's full width between its
/// ears, as tall as its body, not scaled with the sides, asking for the width it wants by the kind of notch it is in, taking a click only
/// where it says so. One that does not have one lays the notch out as it always was.

// MARK: the drawn view

@Observable private final class BodyBox {
    /// What the body asks the notch's width to be on a hardware notch and on a virtual one; nil asks nothing.
    var hardware: CGFloat?
    var virtual: CGFloat?
    /// Which kind of notch the body saw in its environment, and how often it was read (nil: none).
    var seenKind: NotchKind?
    var sawGeometry = false
}

/// An AppKit view in the body that takes a click only on a small rectangle of itself, as the cat's does.
private final class ClickableSpot: NSView {
    var spot = CGRect(x: 10, y: 4, width: 32, height: 20)

    override func hitTest(_ point: NSPoint) -> NSView? {
        spot.contains(convert(point, from: superview)) ? self : nil
    }
}

private struct SpotView: NSViewRepresentable {
    let reference: ViewReference

    func makeNSView(context: Context) -> ClickableSpot {
        let view = ClickableSpot()
        reference.view = view
        return view
    }

    func updateNSView(_ view: ClickableSpot, context: Context) {}
}

private final class ViewReference {
    weak var view: ClickableSpot?
}

private struct BodyView: View {
    let box: BodyBox
    let reference: ViewReference
    @Environment(\.notchGeometry) private var geometry

    var body: some View {
        SpotView(reference: reference)
            .onChange(of: geometry, initial: true) {
                box.seenKind = geometry?.kind
                box.sawGeometry = geometry != nil
            }
            .modifier(Ask(width: geometry?.kind == .hardware ? box.hardware : box.virtual))
    }

    private struct Ask: ViewModifier {
        let width: CGFloat?
        @ViewBuilder func body(content: Content) -> some View {
            if let width { content.notchBodyWidth(width) } else { content }
        }
    }
}

/// The real root view with a collapsed notch whose activity has a body, hosted in a window that is never shown.
@MainActor private struct BodyNotch {
    let hosting: NSHostingView<NotchRootView>
    let window: NSWindow
    let box: BodyBox
    let reference: ViewReference
    let model: NotchViewModel
    let harness: RegistryHarness
    let geometry: NotchGeometry

    static func make(
        _ geometry: NotchGeometry, hardware: CGFloat?, virtual: CGFloat?, look: NotchLook = .classic, shape: NotchGlassShape = .slab,
        strip: Bool = false
    ) async throws -> BodyNotch {
        let harness = RegistryHarness([])
        await harness.registry.bootstrap()
        harness.settings.set(look, for: InterfaceSettings.look)
        harness.settings.set(shape, for: InterfaceSettings.glassShape)
        let theme = NotchTheme(settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let box = BodyBox()
        box.hardware = hardware
        box.virtual = virtual
        let reference = ViewReference()
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        model.hasActivity = true
        harness.activities.set(
            LiveActivity(
                id: "cat", priority: .low, leading: AnyView(Color.clear.frame(width: 16, height: 16)), trailing: AnyView(Color.clear.frame(width: 16, height: 12)),
                bottom: strip ? AnyView(Color.clear) : nil, bottomHeight: strip ? 26 : 0,
                body: AnyView(BodyView(box: box, reference: reference)), summary: "cat"
            ),
            from: "pet"
        )
        let hosting = NSHostingView(
            rootView: NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
        )
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        let notch = BodyNotch(
            hosting: hosting, window: window, box: box, reference: reference, model: model, harness: harness, geometry: geometry
        )
        try await notch.wait("the body was laid out") { reference.view != nil && notch.frame != nil }
        try await notch.settle()
        return notch
    }

    func close() { window.contentView = nil }

    /// The body's view in the hosting view's coordinates, with y measured from the top of the panel.
    var frame: CGRect? {
        guard let view = reference.view, view.window != nil else { return nil }
        let rect = view.convert(view.bounds, to: hosting)
        let top = hosting.isFlipped ? rect.minY : hosting.bounds.height - rect.maxY
        return CGRect(x: rect.minX, y: top, width: rect.width, height: rect.height)
    }

    func wait(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            hosting.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        hosting.layoutSubtreeIfNeeded()
        try #require(condition(), "gave up waiting: \(what)")
    }

    /// Until the body has not moved or changed size for 100 ms: the notch springs to its new width.
    func settle() async throws {
        var last: CGRect?
        var still = 0
        for _ in 0..<1000 {
            hosting.layoutSubtreeIfNeeded()
            if let value = frame, value == last { still += 1 } else { still = 0 }
            if still >= 10 { return }
            last = frame
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(Bool(false), "gave up waiting: the body to settle")
    }

    /// The width of the collapsed notch from the body: the row between the ears, and the ears.
    func notchWidth() throws -> CGFloat {
        try #require(frame).width + 2 * geometry.cornerRadii(for: .compact).top
    }

    /// What a click at `point` (in the body's own coordinates) reaches.
    func hit(at point: CGPoint) throws -> NSView? {
        let view = try #require(reference.view)
        let inHosting = view.convert(point, to: hosting)
        return hosting.hitTest(hosting.superview.map { hosting.convert(inHosting, to: $0) } ?? inHosting)
    }
}

@Suite struct NotchBodyViewTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let notch = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())
    let pill = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))
    let tallPill = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill, pillHeight: 56))

    @Test func theBodyIsDrawnAcrossTheWholeTopRowAtTheNotchsWidthAndAsTallAsItsBodyOnEveryScreenStyleAndLook() async throws {
        for (name, geometry) in [("MacBook", macBook), ("external notch", notch), ("pill", pill), ("tall pill", tallPill)] {
            for (look, shape) in [(NotchLook.classic, NotchGlassShape.slab), (.liquidGlass, .slab), (.liquidGlass, .tiles)] {
                let body = try await BodyNotch.make(geometry, hardware: 420, virtual: 360, look: look, shape: shape)
                defer { body.close() }
                let frame = try #require(body.frame)
                let asked: CGFloat = geometry.kind == .hardware ? 420 : 360
                #expect(abs(frame.width - asked) < 0.01, "\(name) \(look) \(shape): the row is the \(asked) pt it asked for (\(frame.width))")
                #expect(abs(frame.height - geometry.notchSize.height) < 0.01, "\(name) \(look) \(shape): as tall as the body (\(frame.height))")
                #expect(abs(frame.minY - geometry.topGap) < 0.5, "\(name) \(look) \(shape): at the top of the notch's body, below the pill's gap")
                #expect(abs(frame.midX - geometry.panelSize.width / 2) < 0.5, "\(name) \(look) \(shape): centred")
                #expect(abs(try body.notchWidth() - geometry.compactWidth(stripWidth: asked - 2 * NotchTokens.stripPadding)) < 0.01)
            }
        }
    }

    @Test func theBodyIsNotScaledWithTheSidesOnATallPill() async throws {
        #expect(tallPill.collapsedContentScale > 1, "the sides are drawn bigger on this pill")
        let body = try await BodyNotch.make(tallPill, hardware: nil, virtual: 380)
        defer { body.close() }
        let frame = try #require(body.frame)
        let view = try #require(body.reference.view)
        #expect(abs(frame.height - tallPill.notchSize.height) < 0.01, "its own height, and not the pill's times the scale")
        // Its AppKit view is laid out at its own size and sits in a view with no scale on it.
        #expect(abs(view.bounds.height - tallPill.notchSize.height) < 0.01)
        #expect(view.convert(CGSize(width: 10, height: 10), to: body.hosting) == CGSize(width: 10, height: 10))
        #expect(view.window?.contentView === body.hosting)
    }

    @Test func theBodyReadsTheNotchsGeometryAndAsksForItsWidthByKind() async throws {
        let hardware = try await BodyNotch.make(macBook, hardware: 440, virtual: 380)
        defer { hardware.close() }
        #expect(hardware.box.seenKind == .hardware)
        #expect(abs(try #require(hardware.frame).width - 440) < 0.01)
        for geometry in [notch, pill] {
            let virtual = try await BodyNotch.make(geometry, hardware: 440, virtual: 380)
            defer { virtual.close() }
            #expect(virtual.box.seenKind == .virtual)
            #expect(abs(try #require(virtual.frame).width - 380) < 0.01, "the width asked of a virtual notch, not a hardware one")
        }
        #expect(EnvironmentValues().notchGeometry == nil, "and a view outside a notch has none")
    }

    @Test func aBodyThatAsksForLessThanTheNotchHasKeepsTheNotchAndOneThatAsksForMoreIsHeldToTheLimit() async throws {
        for geometry in [macBook, notch, pill] {
            let small = try await BodyNotch.make(geometry, hardware: 60, virtual: 60)
            defer { small.close() }
            #expect(abs(try small.notchWidth() - geometry.compactWidth) < 0.01, "narrower than the notch is: it keeps its width")
            let huge = try await BodyNotch.make(geometry, hardware: 2000, virtual: 2000)
            defer { huge.close() }
            #expect(abs(try huge.notchWidth() - geometry.maximumStripWidth) < 0.01, "held to the limit")
            let silent = try await BodyNotch.make(geometry, hardware: nil, virtual: nil)
            defer { silent.close() }
            #expect(abs(try silent.notchWidth() - geometry.compactWidth) < 0.01, "asking nothing leaves it as wide as it was")
            #expect(silent.model.stripWidth(of: silent.harness.activities) == 0)
        }
    }

    @Test func theWidthFollowsTheBodyAsItChangesAndANarrowerOneByLessThanTheThresholdIsIgnored() async throws {
        for geometry in [macBook, pill] {
            let body = try await BodyNotch.make(geometry, hardware: 400, virtual: 400)
            defer { body.close() }
            func width(after asking: CGFloat) async throws -> CGFloat {
                body.box.hardware = asking
                body.box.virtual = asking
                try await body.wait("the body heard it") { body.frame != nil }
                try await body.settle()
                return try #require(body.frame).width
            }
            #expect(abs(try await width(after: 480) - 480) < 0.01, "wider: at once")
            #expect(abs(try await width(after: 470) - 480) < 0.01, "narrower by 10: no change")
            #expect(abs(try await width(after: 457) - 480) < 0.01, "narrower by 23: no change")
            #expect(abs(try await width(after: 456) - 456) < 0.01, "narrower by 24: taken")
            #expect(abs(try await width(after: 340) - 340) < 0.01, "much narrower: taken")
        }
    }

    @Test func aBodyAndAStripAskTogetherAndTheWiderWins() async throws {
        let body = try await BodyNotch.make(pill, hardware: nil, virtual: 380, strip: true)
        defer { body.close() }
        #expect(abs(try body.notchWidth() - 380) < 0.01)
    }

    @Test func aClickOnTheBodyReachesItOnlyWhereItSaysSoAndTheRestOfTheRowIsTheNotchsOwn() async throws {
        for geometry in [macBook, pill] {
            let body = try await BodyNotch.make(geometry, hardware: 420, virtual: 380)
            defer { body.close() }
            let view = try #require(body.reference.view)
            let spot = view.spot
            #expect(try body.hit(at: CGPoint(x: spot.midX, y: spot.midY)) === view, "a click on the cat is the cat's")
            let elsewhere = CGPoint(x: view.bounds.maxX - 20, y: view.bounds.midY)
            let other = try body.hit(at: elsewhere)
            #expect(other !== view, "a click on the rest of the row goes past the body, to the notch (which opens on it)")
            #expect(other != nil)
        }
    }
}

// MARK: the model and the geometry

@Suite struct NotchBodyModelTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let pill = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))

    func body(_ id: String = "cat", priority: ActivityPriority = .low) -> LiveActivity {
        LiveActivity(id: id, priority: priority, leading: AnyView(Color.clear), trailing: AnyView(Color.clear), body: AnyView(Color.clear), summary: id)
    }

    func plain(_ id: String, priority: ActivityPriority = .normal) -> LiveActivity {
        LiveActivity(id: id, priority: priority, leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: id)
    }

    @Test func theWidthIsReadOnlyWhileTheBodyActivityIsTheCurrentOneAndNeverForAnotherActivityWithNoStrip() {
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        harness.activities.set(body(), from: "pet")
        #expect(harness.activities.currentHasBody)
        #expect(model.stripWidth(of: harness.activities) == 0, "asked nothing yet")
        model.reportStripWidth(400, for: "pet/cat")
        #expect(model.stripWidth(of: harness.activities) == 400)
        model.reportStripWidth(390, for: "pet/cat")
        #expect(model.stripWidth(of: harness.activities) == 400, "the hysteresis of a strip's width")
        // Another activity takes the notch: the notch is as wide as it was without a body, for as long as that lasts.
        harness.activities.set(plain("timer", priority: .high), from: "timer")
        #expect(harness.activities.current?.id == "timer/timer")
        #expect(!harness.activities.currentHasBody)
        #expect(model.stripWidth(of: harness.activities) == 0)
        harness.activities.clear(id: "timer", from: "timer")
        #expect(model.stripWidth(of: harness.activities) == 400, "and back")
        // No strip and no body: no width, whatever was reported for the activity.
        harness.activities.clear(id: "cat", from: "pet")
        harness.activities.set(plain("cat"), from: "pet")
        #expect(model.stripWidth(of: harness.activities) == 0)
    }

    @Test func aBodyDoesNotGiveTheNotchAStrip() {
        let harness = RegistryHarness([])
        harness.activities.set(body(), from: "pet")
        #expect(harness.activities.stripHeight == 0)
        #expect(harness.activities.current?.activity.hasBottom == false)
    }

    @Test func theHitAreaAndTheBubblesFollowTheBodysWidthOnlyWhenThereIsABody() {
        for (screen, geometry) in [(NotchGeometryTests.macBook14, macBook), (NotchGeometryTests.external, pill)] {
            let frame = screen.frame
            let wide: CGFloat = 400
            let grow = geometry.compactWidth(stripWidth: wide) - geometry.compactWidth
            #expect(grow > 0)
            let plainRect = geometry.hitRect(for: .compact, in: frame)
            let inAdded = CGPoint(x: plainRect.maxX + 10, y: frame.maxY - geometry.topGap - 10)
            #expect(geometry.pointerZone(at: inAdded, state: .compact, strip: 0, stripWidth: wide, in: frame) == .outside, "no body, no strip: no width")
            #expect(geometry.pointerZone(at: inAdded, state: .compact, strip: 0, stripWidth: wide, hasBody: true, in: frame) == .notch)
            // The bubbles are where the widened pill's side is, and the zone says so.
            let bubble = geometry.bubbleScreenFrame(at: 0, stripWidth: wide, in: frame)
            let centre = CGPoint(x: bubble.midX, y: bubble.midY)
            #expect(geometry.pointerZone(at: centre, state: .compact, strip: 0, bubbles: 2, stripWidth: wide, hasBody: true, in: frame) == .bubbles)
            #expect(geometry.pointerZone(at: centre, state: .compact, strip: 0, bubbles: 2, listRows: 3, stripWidth: wide, hasBody: true, in: frame) == .bubbles, "and with the list open")
            // The list hangs under all of the widened pill.
            let rightEdge = frame.midX + geometry.centerOffset + geometry.compactWidth(stripWidth: wide) / 2
            let underPill = frame.maxY - geometry.topGap - geometry.notchSize.height - 10
            #expect(geometry.pointerZone(at: CGPoint(x: rightEdge - 6, y: underPill), state: .compact, strip: 0, bubbles: 2, listRows: 3, stripWidth: wide, hasBody: true, in: frame) == .list)
            // Without a body nothing is different from before.
            #expect(
                geometry.pointerZone(at: centre, state: .compact, strip: 0, bubbles: 2, stripWidth: 0, in: frame)
                    == geometry.pointerZone(at: centre, state: .compact, strip: 0, bubbles: 2, stripWidth: 0, hasBody: false, in: frame)
            )
        }
    }
}

// MARK: a body is made of pixels: it is drawn as big as it is

@Suite struct NotchBodyRenderTests {
    @Test func aBodyIsDrawnAtItsOwnSizeWhileTheSidesAreDrawnBiggerOnATallPill() throws {
        let tall = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill, pillHeight: 56))
        #expect(tall.collapsedContentScale == 1.25)
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        model.hasActivity = true
        harness.activities.set(
            LiveActivity(
                id: "a", leading: AnyView(Color.green.frame(width: 16, height: 16)), trailing: AnyView(Color.clear),
                body: AnyView(Color.red.frame(width: 100, height: 10)), summary: "a"
            ),
            from: "m"
        )
        let root = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: tall)
            .frame(width: tall.panelSize.width, height: tall.panelSize.height)
        let renderer = ImageRenderer(content: root)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        func count(_ test: (NSColor) -> Bool, row: Int) -> Int {
            (0..<bitmap.pixelsWide).filter { x in bitmap.colorAt(x: x, y: row).map(test) ?? false }.count
        }
        let row = Int(tall.topGap + tall.notchSize.height / 2)
        let red = count({ $0.redComponent > 0.8 && $0.greenComponent < 0.45 && $0.blueComponent < 0.45 }, row: row)
        let green = count({ $0.greenComponent > 0.5 && $0.redComponent < 0.3 }, row: row)
        #expect(abs(red - 100) <= 1, "the body is 100 pt wide, not 125: \(red)")
        #expect(abs(green - 20) <= 2, "while the side's 16 pt are drawn 1.25 times as big: \(green)")
    }
}

// MARK: a strip for screens with a hardware notch only

@Suite struct NotchStripScopeTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let external = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())

    func activity(scope: BottomScope) -> LiveActivity {
        LiveActivity(
            id: "a", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), bottom: AnyView(Color.white), bottomHeight: 26,
            bottomScope: scope, body: AnyView(Color.clear), summary: "a"
        )
    }

    @Test func theCenterReportsTheStripOnlyToTheScreensItIsFor() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity(scope: .allScreens), from: "m")
        #expect(center.stripHeight(on: .hardware) == 26 && center.stripHeight(on: .virtual) == 26 && center.stripHeight == 26)
        center.set(activity(scope: .hardwareNotchOnly), from: "m")
        #expect(center.stripHeight(on: .hardware) == 26)
        #expect(center.stripHeight(on: .virtual) == 0)
        center.clear(id: "a", from: "m")
        #expect(center.stripHeight(on: .hardware) == 0 && center.stripHeight(on: .virtual) == 0)
    }

    @Test func aStripThatIsNotForAScreenAsksForNoWidthThereButItsBodyStillDoes() {
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        harness.activities.set(activity(scope: .hardwareNotchOnly), from: "m")
        model.reportStripWidth(300, for: "m/a")
        #expect(model.stripWidth(of: harness.activities, on: .hardware) == 300)
        #expect(model.stripWidth(of: harness.activities, on: .virtual) == 300, "its body is there and asks")
        harness.activities.set(
            LiveActivity(
                id: "a", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), bottom: AnyView(Color.white), bottomHeight: 26,
                bottomScope: .hardwareNotchOnly, summary: "a"
            ),
            from: "m"
        )
        #expect(model.stripWidth(of: harness.activities, on: .hardware) == 300)
        #expect(model.stripWidth(of: harness.activities, on: .virtual) == 0, "no body, and a strip that is not for it: nothing asked")
    }

    @Test func theNotchGrowsForTheStripOnAHardwareNotchAndNotOnAVirtualOne() throws {
        func render(_ geometry: NotchGeometry) throws -> NSBitmapImageRep {
            let harness = RegistryHarness([])
            let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
            model.hasActivity = true
            harness.activities.set(activity(scope: .hardwareNotchOnly), from: "m")
            let root = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry)
                .frame(width: geometry.panelSize.width, height: geometry.panelSize.height)
            let renderer = ImageRenderer(content: root)
            renderer.scale = 1
            return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        }
        func whites(_ bitmap: NSBitmapImageRep) -> Int {
            (0..<bitmap.pixelsHigh).reduce(0) { total, y in
                total + (0..<bitmap.pixelsWide).filter { x in bitmap.colorAt(x: x, y: y).map { $0.redComponent > 0.9 && $0.greenComponent > 0.9 && $0.alphaComponent > 0.9 } ?? false }.count
            }
        }
        #expect(whites(try render(macBook)) > 1000, "the strip is under the hardware notch")
        #expect(whites(try render(external)) == 0, "and not under a virtual one")
    }
}

// MARK: no body: the notch as it always was

@Suite struct NotchNoBodyTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let pill = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))

    func render(_ geometry: NotchGeometry, activity: LiveActivity, bubbles: Int = 0) throws -> NSBitmapImageRep {
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        model.hasActivity = true
        harness.activities.set(activity, from: "m")
        for index in 0..<bubbles {
            harness.activities.set(
                LiveActivity(id: "b\(index)", priority: .low, leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "b"),
                from: ModuleID(stringLiteral: "x\(index)")
            )
        }
        model.bubbleCount = CompactAccessories.bubbleCount(activities: harness.activities, geometry: geometry)
        let root = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry)
            .frame(width: geometry.panelSize.width, height: geometry.panelSize.height)
        let renderer = ImageRenderer(content: root)
        renderer.scale = 1
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    func alphas(_ bitmap: NSBitmapImageRep) -> [CGFloat] {
        (0..<bitmap.pixelsHigh).flatMap { y in (0..<bitmap.pixelsWide).map { x in bitmap.colorAt(x: x, y: y)?.alphaComponent ?? -1 } }
    }

    @Test func anActivityWithNoBodyIsDrawnPixelForPixelAsOneWithABodyThatDrawsNothing() throws {
        for geometry in [macBook, pill] {
            for strip in [false, true] {
                func activity(body: AnyView?) -> LiveActivity {
                    LiveActivity(
                        id: "a", priority: .normal, leading: AnyView(Color.clear.frame(width: 16, height: 16)),
                        trailing: AnyView(Color.clear.frame(width: 16, height: 12)), bottom: strip ? AnyView(Color.white) : nil,
                        bottomHeight: strip ? 36 : 0, body: body, summary: "a"
                    )
                }
                for bubbles in [0, 2] {
                    let without = try render(geometry, activity: activity(body: nil), bubbles: bubbles)
                    let empty = try render(geometry, activity: activity(body: AnyView(Color.clear)), bubbles: bubbles)
                    #expect(without.pixelsWide == empty.pixelsWide && without.pixelsHigh == empty.pixelsHigh)
                    #expect(alphas(without) == alphas(empty), "strip \(strip), bubbles \(bubbles)")
                }
            }
        }
    }

    @Test func anActivityWithNoBodyAsksForNoWidthAndIsNotInTheWayOfAStripsWidth() {
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        harness.activities.set(
            LiveActivity(id: "a", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), bottom: AnyView(Color.clear), bottomHeight: 36, summary: "a"),
            from: "m"
        )
        #expect(!harness.activities.currentHasBody)
        #expect(harness.activities.stripHeight == 36)
        model.reportStripWidth(300, for: "m/a")
        #expect(model.stripWidth(of: harness.activities) == 300, "a strip's width goes as it always went")
        #expect(LiveActivity(id: "b", leading: AnyView(Color.clear), trailing: AnyView(Color.clear)).body == nil)
        #expect(!LiveActivity(id: "b", leading: AnyView(Color.clear), trailing: AnyView(Color.clear)).hasBody)
    }
}
