import AppKit
import SwiftUI
import Testing
@testable import NotchUI

/// What a swipe between tabs relies on: a scroll view in a tab keeps every scroll event under it, and what is left over
/// (the tab bar, empty chrome) reaches the hosting view's `onUnusedScroll`. The events are made here and handed to the
/// view AppKit would pick under the pointer; nothing is posted to the system.
@Suite struct ScrollRoutingTests {
    /// 300 x 200: 40 pt of empty chrome, a horizontal scroll view (80 pt), a vertical one (80 pt) with 80 pt wide content in the middle.
    func host() -> (FirstMouseHostingView<some View>, NSWindow) {
        let root = VStack(spacing: 0) {
            Color.clear.frame(height: 40)
            ScrollView(.horizontal) { HStack { ForEach(0..<20, id: \.self) { _ in Color.blue.frame(width: 80, height: 60) } } }.frame(height: 80)
            ScrollView(.vertical) { VStack { ForEach(0..<20, id: \.self) { _ in Color.red.frame(width: 80, height: 30) } } }.frame(height: 80)
        }
        let hosting = FirstMouseHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    /// `hitTest` takes a point in the superview, which is not flipped: y counts up from the bottom.
    func point(x: CGFloat, fromTop y: CGFloat) -> CGPoint { CGPoint(x: x, y: 200 - y) }

    func event(dx: Int32, dy: Int32, phase: CGScrollPhase) throws -> NSEvent {
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0))
        cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        return try #require(NSEvent(cgEvent: cgEvent))
    }

    /// How many of a gesture's events (began, changed) no view under `point` used, for a sideways and an up-down gesture.
    func unused(at point: CGPoint, in hosting: FirstMouseHostingView<some View>) throws -> (sideways: Int, vertical: Int) {
        var count = 0
        hosting.onUnusedScroll = { _ in count += 1 }
        let target = try #require(hosting.hitTest(point))
        var result: [Int] = []
        for (dx, dy) in [(Int32(-40), Int32(0)), (Int32(0), Int32(-40))] {
            count = 0
            target.scrollWheel(with: try event(dx: dx, dy: dy, phase: .began))
            target.scrollWheel(with: try event(dx: dx, dy: dy, phase: .changed))
            result.append(count)
        }
        return (result[0], result[1])
    }

    @Test func emptyChromeHandsEveryEventToTheNotch() throws {
        let (hosting, window) = host()
        let counts = try unused(at: point(x: 40, fromTop: 20), in: hosting)
        #expect(counts.sideways == 2)
        #expect(counts.vertical == 2)
        window.contentView = nil
    }

    @Test func aHorizontalScrollViewKeepsItsEvents() throws {
        let (hosting, window) = host()
        let counts = try unused(at: point(x: 60, fromTop: 80), in: hosting)
        #expect(counts.sideways == 0)
        #expect(counts.vertical == 0)
        window.contentView = nil
    }

    @Test func aVerticalScrollViewKeepsItsEventsToo() throws {
        let (hosting, window) = host()
        let counts = try unused(at: point(x: 150, fromTop: 160), in: hosting)
        #expect(counts.sideways == 0)
        #expect(counts.vertical == 0)
        window.contentView = nil
    }

    @Test func emptySpaceBesideScrollingContentIsChromeAgain() throws {
        let (hosting, window) = host()
        let counts = try unused(at: point(x: 40, fromTop: 160), in: hosting)
        #expect(counts.sideways == 2)
        window.contentView = nil
    }
}
