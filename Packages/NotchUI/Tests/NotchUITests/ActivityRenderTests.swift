import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The bubbles and the list drawn offscreen (no window, no screen): SwiftUI's own layout has to put every bubble where
/// `NotchGeometry` says it is, because the hit areas come from the geometry and the picture from SwiftUI.
@Suite struct ActivityRenderTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())

    func makeCenter(_ count: Int) -> ActivityCenter {
        let center = ActivityCenter(scheduler: ManualScheduler())
        for index in 1...count {
            center.set(LiveActivity(id: "a\(index)", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "Hoạt động \(index)"), from: "m")
        }
        return center
    }

    func render<Content: View>(_ view: Content) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image)
    }

    /// Opacity of the pixel at `point`, measured from the top left of the image: 1 for the bubbles' black, 0 for nothing drawn.
    func alpha(_ bitmap: NSBitmapImageRep, _ point: CGPoint) -> CGFloat {
        bitmap.colorAt(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))?.alphaComponent ?? -1
    }

    func bubbles(_ slots: [ActivitySlot]) -> some View {
        ActivityBubbles(slots: slots, geometry: macBook, label: { $0.id }, activate: { _ in })
    }

    @Test func eachBubbleIsDrawnWhereTheGeometrySaysAndNothingElseIsDrawn() throws {
        for count in 2...4 {
            let center = makeCenter(count)
            let slots = ActivitySlot.bubbles(of: center, capacity: macBook.bubbleCapacity)
            let bitmap = try #require(render(bubbles(slots)))
            // The row is as wide as the panel with the notch's centre line in the middle of it.
            #expect(bitmap.pixelsWide == Int(macBook.panelSize.width))
            #expect(bitmap.pixelsHigh == Int(macBook.bubbleDiameter))
            let middle = macBook.panelSize.width / 2
            for index in slots.indices {
                let frame = macBook.bubbleFrame(at: index)
                #expect(alpha(bitmap, CGPoint(x: middle + frame.midX, y: frame.midY)) == 1, "bubble \(index) of \(count) is black at its centre")
                // Inside the circle near the left and right ends of its middle row, and just outside it.
                #expect(alpha(bitmap, CGPoint(x: middle + frame.minX + 2, y: frame.midY)) == 1)
                #expect(alpha(bitmap, CGPoint(x: middle + frame.maxX - 2, y: frame.midY)) == 1)
                #expect(alpha(bitmap, CGPoint(x: middle + frame.minX + 1, y: 1)) == 0, "the corner of its box is not drawn: it is a circle")
            }
            for index in 0..<(slots.count - 1) {
                let gap = macBook.bubbleFrame(at: index).maxX + NotchGeometry.bubbleGap / 2
                #expect(alpha(bitmap, CGPoint(x: middle + gap, y: macBook.bubbleDiameter / 2)) == 0, "the gap between two bubbles is empty")
            }
            // Left of the first bubble (the notch's side) and right of the last one: nothing.
            #expect(alpha(bitmap, CGPoint(x: middle + macBook.bubbleFrame(at: 0).minX - 3, y: macBook.bubbleDiameter / 2)) == 0)
            #expect(alpha(bitmap, CGPoint(x: middle - 100, y: macBook.bubbleDiameter / 2)) == 0)
            #expect(alpha(bitmap, CGPoint(x: middle + macBook.bubbleFrame(at: slots.count - 1).maxX + 3, y: macBook.bubbleDiameter / 2)) == 0)
        }
    }

    @Test func aNotchlessDisplayDrawsTheSameRowWithSmallerBubbles() throws {
        let geometry = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())
        let slots = ActivitySlot.bubbles(of: makeCenter(3), capacity: geometry.bubbleCapacity)
        let bitmap = try #require(render(ActivityBubbles(slots: slots, geometry: geometry, label: { $0.id }, activate: { _ in })))
        let middle = geometry.panelSize.width / 2
        #expect(bitmap.pixelsHigh == 25)
        for index in slots.indices {
            let frame = geometry.bubbleFrame(at: index)
            #expect(alpha(bitmap, CGPoint(x: middle + frame.midX, y: frame.midY)) == 1)
        }
    }

    @Test func theListIsExactlyAsTallAsTheGeometryHoldsRoomFor() throws {
        for count in 1...(NotchGeometry.maxListRows + 2) {
            let rows = ActivitySlot.listRows(of: makeCenter(count), capacity: NotchGeometry.maxListRows)
            let list = ActivityList(rows: rows, label: { $0.id }, hasTab: { _ in false }, open: { _ in }).frame(width: 301)
            let bitmap = try #require(render(list))
            #expect(CGFloat(bitmap.pixelsHigh) == macBook.listHeight(rows: rows.count), "\(count) activities")
            #expect(rows.count == min(count, NotchGeometry.maxListRows))
        }
    }
}

/// The whole notch view drawn offscreen with and without bubbles and with the list open.
@Suite struct NotchRootRenderTests {
    let harness = RegistryHarness([])
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    var render: ActivityRenderTests { ActivityRenderTests() }

    func makeModel() -> NotchViewModel {
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.milliseconds(150), .milliseconds(300)) })
        model.hasActivity = true
        return model
    }

    func publish(_ count: Int) {
        for index in 1...count {
            harness.activities.set(
                LiveActivity(id: "a\(index)", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "Hoạt động \(index)"), from: "m"
            )
        }
    }

    /// The whole panel, drawn the way the hosting view is sized.
    func draw(_ model: NotchViewModel) throws -> NSBitmapImageRep {
        let root = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: macBook)
            .frame(width: macBook.panelSize.width, height: macBook.panelSize.height)
        return try #require(render.render(root))
    }

    func alpha(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> CGFloat { render.alpha(bitmap, CGPoint(x: x, y: y)) }

    /// Alpha of every pixel in the columns `xs`, top to bottom, to compare two drawings.
    func alphas(_ bitmap: NSBitmapImageRep, columns xs: Range<Int>) -> [CGFloat] {
        (0..<bitmap.pixelsHigh).flatMap { y in xs.map { x in bitmap.colorAt(x: x, y: y)?.alphaComponent ?? -1 } }
    }

    /// The middle of the panel, which is 900 pt wide.
    let middle: CGFloat = 450

    @Test func bubblesAreDrawnBesideThePillAndLeaveItAsItWas() throws {
        let alone = makeModel()
        publish(1)
        let withoutBubbles = try draw(alone)
        publish(4)
        let model = makeModel()
        model.bubbleCount = 2
        let withBubbles = try draw(model)
        // The pill is the same black shape, pixel for pixel, with or without bubbles beside it.
        let pill = Int(middle - 170)..<Int(middle + 161)
        #expect(alphas(withoutBubbles, columns: pill) == alphas(withBubbles, columns: pill))
        #expect(alpha(withoutBubbles, x: middle, y: 16) == 1)
        // Only with other activities are there bubbles, at the places the geometry gives them.
        for index in 0..<2 {
            let frame = macBook.bubbleFrame(at: index)
            #expect(alpha(withoutBubbles, x: middle + frame.midX, y: frame.midY) == 0)
            #expect(alpha(withBubbles, x: middle + frame.midX, y: frame.midY) == 1)
        }
        // And nothing under the pill: no list, no strip.
        #expect(alpha(withBubbles, x: middle, y: 32 + 10) == 0)
    }

    @Test func theOpenListMakesThePillTallerAndLeavesItsWidthAndTheBubbles() throws {
        publish(3)
        let model = makeModel()
        model.bubbleCount = 2
        let closed = try draw(model)
        model.showList()
        #expect(model.isListOpen)
        let open = try draw(model)
        let listHeight = macBook.listHeight(rows: 3)
        // Black under the pill down to the list's end, and not a point below it.
        #expect(alpha(closed, x: middle, y: 32 + 20) == 0)
        #expect(alpha(open, x: middle, y: 32 + 20) == 1)
        #expect(alpha(open, x: middle, y: 32 + listHeight - 12) == 1)
        #expect(alpha(open, x: middle, y: 32 + listHeight + 4) == 0)
        // As wide as the pill was, at the pill's own row.
        let pillRow = 8
        let widths = [closed, open].map { bitmap in (0..<bitmap.pixelsWide).filter { alpha(bitmap, x: CGFloat($0), y: CGFloat(pillRow)) == 1 }.count }
        #expect(widths[0] > 300 && abs(widths[0] - widths[1]) <= 0)
        // The bubbles are still beside it.
        for index in 0..<2 {
            let frame = macBook.bubbleFrame(at: index)
            #expect(alpha(open, x: middle + frame.midX, y: frame.midY) == 1)
        }
    }
}
