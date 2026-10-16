import AppKit
import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import NotchUI

/// A strip under the collapsed notch tells the notch the width it wants (`View.notchStripWidth`): the notch is as wide as the strip's
/// content and its padding, between what it is without a strip and `maximumStripWidth`, with the notch's spring and about its centre.
@Suite struct NotchStripWidthTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let notch = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())
    let pill = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))

    // MARK: how a reported width settles

    @Test func theFirstWidthIsTakenAWiderOneAtOnceAndANarrowerOneOnlyIfItIsNarrowerByTheThreshold() {
        #expect(StripWidth.shrinkThreshold == 24)
        #expect(StripWidth.settle(current: nil, reported: 200) == 200)
        #expect(StripWidth.settle(current: nil, reported: 0) == 0)
        #expect(StripWidth.settle(current: 200, reported: 201) == 201, "wider: at once")
        #expect(StripWidth.settle(current: 200, reported: 500) == 500)
        #expect(StripWidth.settle(current: 200, reported: 200) == 200)
        #expect(StripWidth.settle(current: 200, reported: 190) == 200, "narrower by 10: ignored")
        #expect(StripWidth.settle(current: 200, reported: 176.5) == 200, "by 23.5: ignored")
        #expect(StripWidth.settle(current: 200, reported: 176) == 176, "by 24: taken")
        #expect(StripWidth.settle(current: 200, reported: 20) == 20)
    }

    @Test func linesAboutAsWideAsEachOtherDoNotMakeTheNotchBreatheAndAMuchShorterOneDoes() {
        var width: CGFloat?
        var changes = 0
        for line in [CGFloat(300), 290, 305, 295, 310, 300, 292, 308, 150, 140, 160, 120] {
            let settled = StripWidth.settle(current: width, reported: line)
            if settled != width { changes += 1 }
            width = settled
        }
        // 300, then 305 (wider), 310 (wider), a drop to 150, then 160 (wider) and 120 (under 160 by 40).
        #expect(changes == 6, "\(changes)")
        #expect(width == 120)
    }

    @Test func aStripsWidthBelongsToItsActivityAndTheViewModelAppliesTheThreshold() {
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        #expect(model.stripWidth(for: "a") == 0 && model.stripWidth(for: nil) == 0, "nothing asked")
        model.reportStripWidth(300, for: "a")
        #expect(model.stripWidth(for: "a") == 300)
        #expect(model.stripWidth(for: "b") == 0, "another activity has not asked")
        model.reportStripWidth(290, for: "a")
        #expect(model.stripWidth(for: "a") == 300, "narrower by 10: no change")
        model.reportStripWidth(330, for: "a")
        #expect(model.stripWidth(for: "a") == 330)
        model.reportStripWidth(200, for: "a")
        #expect(model.stripWidth(for: "a") == 200)
        // Another activity starts from its own first width, however much narrower than the last one's.
        model.reportStripWidth(40, for: "b")
        #expect(model.stripWidth(for: "b") == 40 && model.stripWidth(for: "a") == 0)
        model.reportStripWidth(-5, for: "b")
        #expect(model.stripWidth(for: "b") == 0, "a negative width is no width: 0, which is not a request")
    }

    // MARK: the width of the collapsed notch

    @Test func noWidthAskedChangesNothing() {
        for geometry in [macBook, notch, pill] {
            let base = geometry.compactWidth
            #expect(geometry.compactWidth(stripWidth: 0) == base)
            #expect(geometry.shapeSize(for: .compact, bottomHeight: 36, stripWidth: 0) == geometry.shapeSize(for: .compact, bottomHeight: 36))
            #expect(geometry.shapeSize(for: .compact).width == base)
            #expect(geometry.hitRect(for: .compact, bottomHeight: 36, stripWidth: 0, in: NotchGeometryTests.macBook14.frame)
                == geometry.hitRect(for: .compact, bottomHeight: 36, in: NotchGeometryTests.macBook14.frame))
            #expect(geometry.bubbleFrame(at: 0, stripWidth: 0) == geometry.bubbleFrame(at: 0))
        }
        // The widths a notch had before.
        #expect(macBook.compactWidth == 325 && notch.compactWidth == 325 && pill.compactWidth == 313)
    }

    @Test func aStripThatAsksGetsWhatItAsksForAndThePaddingBetweenTheClamps() {
        // Ears of 6 on a notch, none on a pill, and `stripPadding` each side.
        #expect(NotchTokens.stripPadding == 12)
        #expect(macBook.compactWidth(stripWidth: 400) == CGFloat(400 + 2 * 6 + 2 * 12))
        #expect(notch.compactWidth(stripWidth: 400) == 436)
        #expect(pill.compactWidth(stripWidth: 400) == CGFloat(400 + 2 * 12))
        // Never narrower than it is without a strip.
        for geometry in [macBook, notch, pill] {
            #expect(geometry.compactWidth(stripWidth: 20) == geometry.compactWidth)
            #expect(geometry.compactWidth(stripWidth: 1) == geometry.compactWidth)
        }
        // Never wider than the limit, and the limit is the open width held to 560.
        #expect(NotchGeometry.stripWidthLimit == 560)
        for geometry in [macBook, notch, pill] {
            #expect(geometry.maximumStripWidth == 560)
            #expect(geometry.compactWidth(stripWidth: 5000) == 560)
            #expect(geometry.compactWidth(stripWidth: .infinity) == 560)
        }
        let narrowOpen = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(openWidth: 480))
        #expect(narrowOpen.maximumStripWidth == 480 && narrowOpen.compactWidth(stripWidth: 5000) == 480)
        // A collapsed notch that is already wider than that keeps its width.
        let wide = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchWidth: 300, openWidth: 480))
        #expect(wide.compactWidth == 440 && wide.maximumStripWidth == 480)
        let widest = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchWidth: 300, openWidth: 480, virtualNotchStyle: .pill))
        #expect(widest.compactWidth(stripWidth: 5000) >= widest.compactWidth)
    }

    @Test func theWidthIsTheCollapsedNotchWithAStripAndNothingElse() {
        for geometry in [macBook, notch, pill] {
            let wide = geometry.shapeSize(for: .compact, bottomHeight: 36, stripWidth: 400)
            #expect(wide.width == geometry.compactWidth(stripWidth: 400))
            #expect(wide.height == geometry.notchSize.height + 36, "the height is the strip's, as before")
            // The width is the strip's whatever is under the notch (the open list is not the strip's, and the notch does not change
            // when it opens); a caller with no strip passes none.
            #expect(geometry.shapeSize(for: .compact, bottomHeight: geometry.listHeight(rows: 3), stripWidth: 400).width == geometry.compactWidth(stripWidth: 400))
            #expect(geometry.shapeSize(for: .compact, bottomHeight: 0, stripWidth: 0).width == geometry.compactWidth)
            for state in [NotchState.closed, .open("a"), .open(nil), .toast] {
                #expect(geometry.shapeSize(for: state, contentHeight: 190, bottomHeight: 36, stripWidth: 400) == geometry.shapeSize(for: state, contentHeight: 190), "\(state)")
            }
        }
    }

    @Test func theHitAreaAndTheBubblesFollowTheWidthAndTheBubblesStayBesideThePillWithTheSameGap() {
        for (screen, geometry) in [(NotchGeometryTests.macBook14, macBook), (NotchGeometryTests.external, notch), (NotchGeometryTests.external, pill)] {
            let frame = screen.frame
            let plain = geometry.hitRect(for: .compact, bottomHeight: 36, in: frame)
            let wide = geometry.hitRect(for: .compact, bottomHeight: 36, stripWidth: 450, in: frame)
            let grow = geometry.compactWidth(stripWidth: 450) - geometry.compactWidth
            #expect(grow > 0)
            #expect(wide.width - plain.width == grow && plain.minX - wide.minX == grow / 2, "centred: it grows about its centre")
            #expect(wide.height == plain.height)
            // The drag area too.
            #expect(geometry.dragHitRect(for: .compact, bottomHeight: 36, stripWidth: 450, in: frame).width - geometry.dragHitRect(for: .compact, bottomHeight: 36, in: frame).width == grow)
            // A point in the added width is on the notch only with the width.
            let inAdded = CGPoint(x: plain.maxX + 10, y: frame.maxY - geometry.topGap - 10)
            #expect(geometry.pointerZone(at: inAdded, state: .compact, strip: 36, in: frame) == .outside)
            #expect(geometry.pointerZone(at: inAdded, state: .compact, strip: 36, stripWidth: 450, in: frame) == .notch)
            // The bubbles are the gap from the pill's end, wherever it ends.
            for index in 0..<NotchGeometry.maxBubbles {
                let bubble = geometry.bubbleFrame(at: index, stripWidth: 450)
                #expect(bubble.minX - geometry.bubbleFrame(at: index).minX == grow / 2)
            }
            let bodyEnd = geometry.compactWidth(stripWidth: 450) / 2 - geometry.cornerRadii(for: .compact).top
            #expect(geometry.bubbleFrame(at: 0, stripWidth: 450).minX - bodyEnd == NotchGeometry.bubbleGap, "the gap from the pill's body")
            let first = geometry.bubbleScreenFrame(at: 0, stripWidth: 450, in: frame)
            #expect(geometry.pointerZone(at: CGPoint(x: first.midX, y: first.midY), state: .compact, strip: 36, bubbles: 2, stripWidth: 450, in: frame) == .bubbles)
        }
    }

    @Test func theOpenListLeavesTheNotchAsWideAsItsStripAndTheBubblesWhereTheyAreUnderThePointerThatOpenedIt() {
        // The list opens when the pointer hovers a bubble. If the notch narrowed then, the bubble would slide out from under the pointer, the
        // list would close, the notch would widen again, and so on.
        for (screen, geometry) in [(NotchGeometryTests.macBook14, macBook), (NotchGeometryTests.external, notch), (NotchGeometryTests.external, pill)] {
            let frame = screen.frame
            let first = geometry.bubbleScreenFrame(at: 0, stripWidth: 450, in: frame)
            let centre = CGPoint(x: first.midX, y: first.midY)
            #expect(geometry.pointerZone(at: centre, state: .compact, strip: 36, bubbles: 2, listRows: 0, stripWidth: 450, in: frame) == .bubbles)
            #expect(
                geometry.pointerZone(at: centre, state: .compact, strip: 36, bubbles: 2, listRows: 3, stripWidth: 450, in: frame) == .bubbles,
                "the same bubble, under the same pointer, with the list open"
            )
            // The pill is as wide with the list open: its added width is still the notch, and the list hangs under all of it.
            let wide = geometry.compactWidth(stripWidth: 450)
            let rightEdge = frame.midX + geometry.centerOffset + wide / 2
            #expect(geometry.pointerZone(at: CGPoint(x: rightEdge - 6, y: frame.maxY - geometry.topGap - 10), state: .compact, strip: 36, bubbles: 2, listRows: 3, stripWidth: 450, in: frame) == .notch)
            let underPill = frame.maxY - geometry.topGap - geometry.notchSize.height - 10
            #expect(geometry.pointerZone(at: CGPoint(x: rightEdge - 6, y: underPill), state: .compact, strip: 36, bubbles: 2, listRows: 3, stripWidth: 450, in: frame) == .list, "the list is as wide as the pill")
            // With no strip the list does not widen anything.
            let plain = geometry.bubbleScreenFrame(at: 0, in: frame)
            #expect(geometry.pointerZone(at: CGPoint(x: plain.midX, y: plain.midY), state: .compact, strip: 0, bubbles: 2, listRows: 3, stripWidth: 450, in: frame) == .bubbles)
        }
    }

    @Test func theBubblesAlwaysFitBesideTheWidestPillAndTheirNumberDoesNotChangeWithTheStrip() {
        for config in [
            NotchLayoutConfig(), NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, openWidth: 900),
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, openWidth: 480, virtualNotchStyle: .pill),
            NotchLayoutConfig(virtualNotchWidth: 120, virtualNotchHeight: 24, openWidth: 900, virtualNotchStyle: .pill),
        ] {
            for screen in [NotchGeometryTests.macBook14, NotchGeometryTests.external] {
                let geometry = NotchGeometry(screen: screen, config: config)
                #expect(geometry.bubbleCapacity == NotchGeometry.maxBubbles, "\(config)")
                for index in 0..<geometry.bubbleCapacity {
                    #expect(geometry.bubbleFrame(at: index, stripWidth: .infinity).maxX <= geometry.panelSize.width / 2)
                }
                #expect(geometry.compactWidth(stripWidth: .infinity) <= geometry.panelSize.width)
            }
        }
    }
}

// MARK: the drawn view

@Observable private final class StripBox {
    var width: CGFloat?
}

private final class StripProbe {
    /// The strip's own view: its frame in the window, which is as wide as the notch leaves it.
    var frame: CGRect?
}

private struct StripView: View {
    let box: StripBox
    let probe: StripProbe

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [probe] in probe.frame = $0 }
            .modifier(Report(width: box.width))
    }

    private struct Report: ViewModifier {
        let width: CGFloat?
        @ViewBuilder func body(content: Content) -> some View {
            if let width { content.notchStripWidth(width) } else { content }
        }
    }
}

/// The real root view with a collapsed notch whose activity has a strip, hosted in a window that is never shown.
@MainActor private struct StripNotch {
    let hosting: NSHostingView<NotchRootView>
    let window: NSWindow
    let box: StripBox
    let probe: StripProbe
    let model: NotchViewModel
    let geometry: NotchGeometry

    static func make(
        _ geometry: NotchGeometry, width: CGFloat?, look: NotchLook = .classic, shape: NotchGlassShape = .slab, bubbles: Int = 0
    ) async throws -> StripNotch {
        let harness = RegistryHarness([])
        await harness.registry.bootstrap()
        harness.settings.set(look, for: InterfaceSettings.look)
        harness.settings.set(shape, for: InterfaceSettings.glassShape)
        let theme = NotchTheme(settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let box = StripBox()
        box.width = width
        let probe = StripProbe()
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        model.hasActivity = true
        harness.activities.set(
            LiveActivity(
                id: "lyrics", leading: AnyView(Color.clear.frame(width: 16, height: 16)), trailing: AnyView(Color.clear.frame(width: 16, height: 12)),
                bottom: AnyView(StripView(box: box, probe: probe)), bottomHeight: 36, summary: "lyrics"
            ),
            from: "media"
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
        let notch = StripNotch(hosting: hosting, window: window, box: box, probe: probe, model: model, geometry: geometry)
        try await notch.wait("the strip was laid out") { probe.frame != nil }
        try await notch.settle()
        return notch
    }

    func close() { window.contentView = nil }

    func wait(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            hosting.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        hosting.layoutSubtreeIfNeeded()
        try #require(condition(), "gave up waiting: \(what)")
    }

    /// Until the strip has not moved or changed size for 100 ms: the notch springs to its new width.
    func settle() async throws {
        var last: CGRect?
        var still = 0
        for _ in 0..<1000 {
            hosting.layoutSubtreeIfNeeded()
            if let value = probe.frame, value == last { still += 1 } else { still = 0 }
            if still >= 10 { return }
            last = probe.frame
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(Bool(false), "gave up waiting: the strip to settle")
    }

    /// What the notch's width is, from the strip: its width, the ears and the padding on both sides.
    func notchWidth() throws -> CGFloat {
        try #require(probe.frame).width + 2 * geometry.cornerRadii(for: .compact).top + 2 * NotchTokens.stripPadding
    }
}

@Suite struct NotchStripWidthViewTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let notch = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())
    let pill = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))

    @Test func theNotchIsAsWideAsItsStripAsksOnEveryScreenStyleAndLook() async throws {
        for (name, geometry) in [("MacBook", macBook), ("external notch", notch), ("pill", pill)] {
            for (look, shape) in [(NotchLook.classic, NotchGlassShape.slab), (.liquidGlass, .slab), (.liquidGlass, .tiles)] {
                let strip = try await StripNotch.make(geometry, width: 400, look: look, shape: shape)
                defer { strip.close() }
                let frame = try #require(strip.probe.frame)
                #expect(abs(frame.width - 400) < 0.01, "\(name) \(look) \(shape): the strip gets the 400 pt it asked for (\(frame.width))")
                #expect(abs(try strip.notchWidth() - geometry.compactWidth(stripWidth: 400)) < 0.01)
                #expect(abs(frame.midX - geometry.panelSize.width / 2) < 0.5, "\(name) \(look) \(shape): centred")
            }
        }
    }

    @Test func aStripThatAsksForLessThanTheNotchHasKeepsTheNotchAndOneThatAsksForMoreIsHeldToTheLimit() async throws {
        for geometry in [macBook, notch, pill] {
            let small = try await StripNotch.make(geometry, width: 60)
            defer { small.close() }
            #expect(abs(try small.notchWidth() - geometry.compactWidth) < 0.01, "narrower than the notch is: it keeps its width")
            let huge = try await StripNotch.make(geometry, width: 2000)
            defer { huge.close() }
            #expect(abs(try huge.notchWidth() - geometry.maximumStripWidth) < 0.01, "held to the limit")
        }
    }

    @Test func aStripThatAsksForNothingLeavesTheNotchAsWideAsItWas() async throws {
        for geometry in [macBook, notch, pill] {
            let silent = try await StripNotch.make(geometry, width: nil)
            defer { silent.close() }
            #expect(abs(try silent.notchWidth() - geometry.compactWidth) < 0.01)
            #expect(silent.model.stripWidth(for: "lyrics") == 0)
        }
    }

    @Test func theWidthFollowsTheStripAsItChangesAndANarrowerLineByLessThanTheThresholdIsIgnored() async throws {
        for geometry in [macBook, pill] {
            let strip = try await StripNotch.make(geometry, width: 400)
            defer { strip.close() }
            func width(after asking: CGFloat) async throws -> CGFloat {
                strip.box.width = asking
                try await strip.wait("the strip heard it") { strip.probe.frame != nil }
                try await strip.settle()
                return try #require(strip.probe.frame).width
            }
            #expect(abs(try await width(after: 480) - 480) < 0.01, "wider: at once")
            #expect(abs(try await width(after: 470) - 480) < 0.01, "narrower by 10: no change")
            #expect(abs(try await width(after: 457) - 480) < 0.01, "narrower by 23: no change")
            #expect(abs(try await width(after: 456) - 456) < 0.01, "narrower by 24: taken")
            #expect(abs(try await width(after: 340) - 340) < 0.01, "much narrower: taken")
            #expect(abs(try await width(after: 350) - 350) < 0.01, "wider again")
        }
    }

    @Test func theBubblesAreBesideThePillWhereverItsWidthEnds() async throws {
        let strip = try await StripNotch.make(macBook, width: 450, bubbles: 2)
        defer { strip.close() }
        let wide = macBook.compactWidth(stripWidth: 450)
        #expect(abs(try strip.notchWidth() - wide) < 0.01)
        #expect(wide > macBook.compactWidth)
        // (The layout of the bubbles is the geometry's, which has its own tests; here the notch is built with them and lays out.)
        #expect(strip.model.bubbleCount == 2)
    }
}
