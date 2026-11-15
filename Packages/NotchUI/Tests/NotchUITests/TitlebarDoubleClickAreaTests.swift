import AppKit
import SwiftUI
import Testing
@testable import NotchUI

@MainActor
private final class SpyWindow: TitlebarWindowActing {
    var zoomCount = 0
    var minimizeCount = 0
    var dragCount = 0

    func performZoom(_ sender: Any?) {
        zoomCount += 1
    }

    func performMiniaturize(_ sender: Any?) {
        minimizeCount += 1
    }

    func performDrag(with event: NSEvent) {
        dragCount += 1
    }
}

private func makeMouseEvent(type: NSEvent.EventType = .leftMouseDown, location: CGPoint = CGPoint(x: 10, y: 10), clickCount: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: clickCount,
        pressure: 1
    )!
}

private func makeDragEvent(location: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDragged,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    )!
}

private func makeUpEvent(location: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    )!
}

private func findAncestor<T: NSView>(of view: NSView?, type: T.Type) -> T? {
    var curr = view
    while let v = curr {
        if let match = v as? T { return match }
        curr = v.superview
    }
    return nil
}

@Suite
@MainActor
struct TitlebarDoubleClickAreaTests {

    // TB-1: Happy Path - mouseDown(1) does NOT drag; mouseDragged >= 3pt calls performDrag once
    @Test
    func test_TB1_dragGestureDefersUntilThreshold() {
        let view = TitlebarInteractionView()
        let spy = SpyWindow()
        view.actorOverride = spy

        view.mouseDown(with: makeMouseEvent(location: CGPoint(x: 10, y: 10), clickCount: 1))
        #expect(spy.dragCount == 0)
        #expect(spy.zoomCount == 0)

        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 20, y: 10))) // delta = 10pt >= 3pt
        #expect(spy.dragCount == 1)
        #expect(spy.zoomCount == 0)

        view.mouseUp(with: makeUpEvent(location: CGPoint(x: 20, y: 10)))
        #expect(spy.dragCount == 1)
    }

    // TB-2: Happy Path - True Double Click Sequence (down(1) -> up -> down(2)) with Maximize calls performZoom
    @Test
    func test_TB2_trueDoubleClickSequence_callsZoomOnce() {
        let view = TitlebarInteractionView()
        let spy = SpyWindow()
        view.preferenceProvider = { "Maximize" }
        view.actorOverride = spy

        view.mouseDown(with: makeMouseEvent(location: CGPoint(x: 10, y: 10), clickCount: 1))
        #expect(spy.dragCount == 0)
        view.mouseUp(with: makeUpEvent(location: CGPoint(x: 10, y: 10)))

        view.mouseDown(with: makeMouseEvent(location: CGPoint(x: 10, y: 10), clickCount: 2))
        #expect(spy.zoomCount == 1)
        #expect(spy.dragCount == 0)
        #expect(spy.minimizeCount == 0)
    }

    // TB-3: Edge - mouseDragged below 3pt threshold does NOT trigger performDrag
    @Test
    func test_TB3_dragBelowThreshold_doesNotTriggerDrag() {
        let view = TitlebarInteractionView()
        let spy = SpyWindow()
        view.actorOverride = spy

        view.mouseDown(with: makeMouseEvent(location: CGPoint(x: 10, y: 10), clickCount: 1))
        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 12, y: 10))) // delta = 2pt < 3pt
        #expect(spy.dragCount == 0)

        view.mouseUp(with: makeUpEvent(location: CGPoint(x: 12, y: 10)))
        #expect(spy.dragCount == 0)
    }

    // TB-4: Edge - repeated mouseDragged calls only invoke performDrag once per gesture
    @Test
    func test_TB4_repeatedDragEvents_callPerformDragOncePerGesture() {
        let view = TitlebarInteractionView()
        let spy = SpyWindow()
        view.actorOverride = spy

        view.mouseDown(with: makeMouseEvent(location: CGPoint(x: 10, y: 10), clickCount: 1))
        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 20, y: 10)))
        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 30, y: 10)))
        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 40, y: 10)))
        #expect(spy.dragCount == 1)

        view.mouseUp(with: makeUpEvent(location: CGPoint(x: 40, y: 10)))

        // New gesture begins
        view.mouseDown(with: makeMouseEvent(location: CGPoint(x: 50, y: 10), clickCount: 1))
        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 60, y: 10)))
        #expect(spy.dragCount == 2)
    }

    // TB-5: Edge - drag after double-click does NOT drag
    @Test
    func test_TB5_dragAfterDoubleClick_doesNotDrag() {
        let view = TitlebarInteractionView()
        let spy = SpyWindow()
        view.preferenceProvider = { "Maximize" }
        view.actorOverride = spy

        view.mouseDown(with: makeMouseEvent(location: CGPoint(x: 10, y: 10), clickCount: 2))
        #expect(spy.zoomCount == 1)

        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 30, y: 10)))
        #expect(spy.dragCount == 0)
    }

    // TB-6: Edge - triple click does not zoom or drag
    @Test
    func test_TB6_tripleClick_doesNotZoomOrDrag() {
        let view = TitlebarInteractionView()
        let spy = SpyWindow()
        view.actorOverride = spy

        view.mouseDown(with: makeMouseEvent(location: CGPoint(x: 10, y: 10), clickCount: 3))
        #expect(spy.zoomCount == 0)
        #expect(spy.minimizeCount == 0)
        #expect(spy.dragCount == 0)

        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 30, y: 10)))
        #expect(spy.dragCount == 0)
    }

    // TB-7: Edge - Preference Minimize and None
    @Test
    func test_TB7_preferences_minimizeAndNone() {
        #expect(TitlebarDoubleClickAction.resolve(preference: "Minimize") == .minimize)
        #expect(TitlebarDoubleClickAction.resolve(preference: "None") == .none)
        #expect(TitlebarDoubleClickAction.resolve(preference: "Maximize") == .zoom)
        #expect(TitlebarDoubleClickAction.resolve(preference: nil) == .zoom)
        #expect(TitlebarDoubleClickAction.resolve(preference: "garbage") == .zoom)

        let view = TitlebarInteractionView()
        let spy = SpyWindow()
        view.actorOverride = spy
        view.preferenceProvider = { "Minimize" }

        view.mouseDown(with: makeMouseEvent(clickCount: 2))
        #expect(spy.minimizeCount == 1)
        #expect(spy.zoomCount == 0)
        #expect(spy.dragCount == 0)

        view.preferenceProvider = { "None" }
        view.mouseDown(with: makeMouseEvent(clickCount: 2))
        #expect(spy.minimizeCount == 1)
        #expect(spy.zoomCount == 0)
        #expect(spy.dragCount == 0)
    }

    // TB-8: Negative - nil actor / no window handles drag/up gracefully
    @Test
    func test_TB8_noActor_doesNotCrash() {
        let view = TitlebarInteractionView()
        view.actorOverride = nil

        // Without mouseDown
        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 30, y: 10)))
        view.mouseUp(with: makeUpEvent(location: CGPoint(x: 30, y: 10)))

        // With mouseDown
        view.mouseDown(with: makeMouseEvent(clickCount: 1))
        view.mouseDragged(with: makeDragEvent(location: CGPoint(x: 30, y: 10)))
        view.mouseUp(with: makeUpEvent(location: CGPoint(x: 30, y: 10)))
    }

    // TB-9: Empirical Hit-Testing with ignoresSafeArea(.container, edges: .top)
    @Test
    func test_TB9_hitTest_withIgnoresSafeArea_topEdgeHitTitlebarArea() {
        struct TestHeaderWithSafeArea: View {
            var body: some View {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Sidebar")
                            Spacer()
                        }
                        .frame(height: 52)
                        .background(TitlebarDoubleClickArea())
                        Spacer()
                    }
                    .frame(width: 230)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Title")
                            Spacer()
                            Button("Action") {}
                        }
                        .frame(height: 52)
                        .background(TitlebarDoubleClickArea())
                        Spacer()
                    }
                }
                .frame(width: 800, height: 600)
                .ignoresSafeArea(.container, edges: .top)
            }
        }

        let hosting = NSHostingView(rootView: TestHeaderWithSafeArea())
        hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()

        // Point near top edge in header (x=400, y=height - 4 = 596)
        let hitTopHeader = hosting.hitTest(NSPoint(x: 400, y: 596))
        #expect(findAncestor(of: hitTopHeader, type: TitlebarInteractionView.self) != nil)

        // Point near top edge in sidebar empty area (x=180, y=height - 4 = 596)
        let hitTopSidebar = hosting.hitTest(NSPoint(x: 180, y: 596))
        #expect(findAncestor(of: hitTopSidebar, type: TitlebarInteractionView.self) != nil)
    }

    // TB-9b: Control Test - Without ignoresSafeArea
    @Test
    func test_TB9b_hitTest_withoutIgnoresSafeArea_recordsInsets() {
        struct TestHeaderWithoutSafeArea: View {
            var body: some View {
                HStack(spacing: 0) {
                    Text("Sidebar").frame(width: 230).background(TitlebarDoubleClickArea())
                    VStack {
                        Text("Title").frame(height: 52).background(TitlebarDoubleClickArea())
                        Spacer()
                    }
                }
                .frame(width: 800, height: 600)
            }
        }

        let hosting = NSHostingView(rootView: TestHeaderWithoutSafeArea())
        hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()

        #expect(hosting.frame.size.height == 600)
    }

    // TB-10: Regression Tests preserved
    @Test
    func test_TB10_view_flags() {
        let view = TitlebarInteractionView()
        #expect(view.mouseDownCanMoveWindow == false)
        #expect(view.acceptsFirstMouse(for: nil) == true)
    }

    @Test
    func test_TB10_hitTest_emptyAreaRoutesToInteractionView_buttonDoesNot() {
        struct TestHeader: View {
            var body: some View {
                HStack {
                    Text("x")
                    Spacer()
                    Button("b") {}
                }
                .padding(.horizontal, 18)
                .frame(width: 400, height: 52)
                .background(TitlebarDoubleClickArea())
            }
        }

        let hosting = NSHostingView(rootView: TestHeader())
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 52)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 52),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        // Hit test at Spacer area (x=200, y=26)
        let hitSpacer = hosting.hitTest(NSPoint(x: 200, y: 26))
        let interactionView = findAncestor(of: hitSpacer, type: TitlebarInteractionView.self)
        #expect(interactionView != nil)

        // Hit test at Button area (trailing, x=380, y=26)
        let hitButton = hosting.hitTest(NSPoint(x: 380, y: 26))
        #expect(!(hitButton is TitlebarInteractionView))
    }
}
