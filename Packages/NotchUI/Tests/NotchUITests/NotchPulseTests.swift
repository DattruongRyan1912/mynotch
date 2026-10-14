import AppKit
import SwiftUI
import Testing
@testable import NotchUI

@Suite struct NotchPulseTests {
    typealias Pulse = NotchPulse<Image>

    func glyph() -> Image { Image(systemName: "sparkle") }

    @Test func activeContentRepeatsAnOpacityAnimationOnItsOwnLayer() throws {
        let view = NotchPulseView(content: glyph())
        view.setPulsing(true)
        let animation = try #require(view.host.layer?.animation(forKey: NotchPulseView<Image>.animationKey) as? CABasicAnimation)
        #expect(animation.keyPath == "opacity")
        #expect(animation.fromValue as? Float == 1)
        #expect(animation.toValue as? Float == Pulse.dimmedOpacity)
        #expect(animation.duration == Pulse.halfPeriod)
        #expect(animation.autoreverses)
        #expect(animation.repeatCount == .infinity)
        // The view's own layer is left to SwiftUI, whose transitions set its opacity.
        #expect(view.layer?.animationKeys() == nil)
    }

    @Test func stoppingRemovesTheAnimationAndStartingAgainAddsOneAnimation() {
        let view = NotchPulseView(content: glyph())
        view.setPulsing(true)
        view.setPulsing(true)
        #expect(view.host.layer?.animationKeys() == [NotchPulseView<Image>.animationKey])
        view.setPulsing(false)
        #expect(!view.isPulsing)
        view.setPulsing(true)
        #expect(view.isPulsing)
    }

    @Test func inactiveContentNeverAnimates() {
        let view = NotchPulseView(content: glyph())
        view.setPulsing(false)
        #expect(!view.isPulsing)
    }

    @Test func clicksAndHoversBelongToTheViewItSitsIn() {
        let view = NotchPulseView(content: glyph())
        view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        #expect(view.hitTest(CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func theHostedContentFillsTheView() {
        let view = NotchPulseView(content: glyph().font(.system(size: 14, weight: .semibold)))
        view.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        view.layoutSubtreeIfNeeded()
        #expect(view.host.frame == view.bounds)
    }

    @Test func itReportsTheSizeOfItsContent() {
        let view = NotchPulseView(content: Color.clear.frame(width: 16, height: 14))
        #expect(view.host.intrinsicContentSize == CGSize(width: 16, height: 14))
    }

    func find<V: NSView>(_ type: V.Type, in view: NSView) -> V? {
        if let match = view as? V { return match }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    /// SwiftUI's own make and update of the pulse, in a window that is never shown.
    func host<Root: View>(_ root: Root) -> (FirstMouseHostingView<Root>, NSWindow) {
        let hosting = FirstMouseHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 60, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    @Test func swiftUIMakesAViewThatPulsesWhileActive() throws {
        let (hosting, window) = host(glyph().notchPulse(isActive: true))
        let view = try #require(find(NotchPulseView<Image>.self, in: hosting))
        #expect(view.isPulsing)
        window.contentView = nil
    }

    @Test func swiftUIDoesNotPulseAnInactiveGlyph() throws {
        let (hosting, window) = host(glyph().notchPulse(isActive: false))
        let view = try #require(find(NotchPulseView<Image>.self, in: hosting))
        #expect(!view.isPulsing)
        window.contentView = nil
    }

    @Test func theAnimationStopsWhileTheNotchIsOffScreenAndComesBack() throws {
        let (hosting, window) = host(glyph().notchPulse(isActive: true).environment(\.notchIsOnScreen, false))
        let view = try #require(find(NotchPulseView<Image>.self, in: hosting))
        #expect(!view.isPulsing)
        hosting.rootView = glyph().notchPulse(isActive: true).environment(\.notchIsOnScreen, true)
        hosting.layoutSubtreeIfNeeded()
        #expect(view.isPulsing)
        window.contentView = nil
    }

    #if DEBUG
    /// The point of it: a pulse that SwiftUI redrew every frame would keep the hosting view laying out.
    @Test func pulsingNeverMakesTheHostingViewLayOutAgain() {
        let (hosting, window) = host(glyph().notchPulse(isActive: true))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let settled = NotchPerf.counted(.layouts)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        #expect(NotchPerf.counted(.layouts) == settled)
        #expect(!hosting.needsLayout)
        window.contentView = nil
    }
    #endif
}
