import AppKit
import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct PinnedWindowTests {
    private static func makeTestImage(width: Int = 200, height: Int = 100) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    @Test func stateMaintainsAspectRatioUnderZoom() {
        var state = PinnedWindowState(baseSize: CGSize(width: 400, height: 200))
        #expect(state.currentSize == CGSize(width: 400, height: 200))

        let currentFrame = CGRect(x: 100, y: 100, width: 400, height: 200)
        let zoomedFrame = state.setZoom(1.5, currentFrame: currentFrame)
        #expect(state.zoom == 1.5)
        #expect(zoomedFrame.width == 600)
        #expect(zoomedFrame.height == 300)

        // Clamped at maxZoom
        _ = state.setZoom(10.0, currentFrame: zoomedFrame)
        #expect(state.zoom == PinnedWindowState.maxZoom)

        // Clamped at minZoom
        _ = state.setZoom(0.01, currentFrame: zoomedFrame)
        #expect(state.zoom == PinnedWindowState.minZoom)
    }

    @Test func stateEnforcesMinimumDimension() {
        var state = PinnedWindowState(baseSize: CGSize(width: 80, height: 40))
        // minDimension is 60, so height 40 is scaled up to 60, width 80 scaled to 120
        #expect(state.currentSize.height >= PinnedWindowState.minDimension)
        #expect(state.currentSize.width >= state.currentSize.height)

        let frame = CGRect(origin: .zero, size: state.currentSize)
        _ = state.setZoom(0.25, currentFrame: frame)
        #expect(state.currentSize.height >= PinnedWindowState.minDimension)
    }

    @Test func stateAnchorsZoomCorrectly() {
        var state = PinnedWindowState(baseSize: CGSize(width: 200, height: 100))
        let frame = CGRect(x: 50, y: 50, width: 200, height: 100)
        let anchor = CGPoint(x: 50, y: 50) // (0.25, 0.5)

        let newFrame = state.setZoom(2.0, currentFrame: frame, anchorInWindow: anchor)
        #expect(newFrame.width == 400)
        #expect(newFrame.height == 200)
        // Anchor in global points before: 50 + 50 = 100, 50 + 50 = 100
        // Anchor in global points after: newFrame.minX + 400 * 0.25 = newFrame.minX + 100 = 100 -> newFrame.minX = 0
        #expect(abs(newFrame.minX - 0) < 0.001)
        #expect(abs(newFrame.minY - 0) < 0.001)
    }

    @Test func stateClampsOpacity() {
        var state = PinnedWindowState(baseSize: CGSize(width: 100, height: 100))
        #expect(state.opacity == 1.0)

        state.setOpacity(0.5)
        #expect(state.opacity == 0.5)

        state.setOpacity(2.0)
        #expect(state.opacity == PinnedWindowState.maxOpacity)

        state.setOpacity(0.05)
        #expect(state.opacity == PinnedWindowState.minOpacity)
    }

    @Test func initialFrameRespectsSourceFrameAndBounds() {
        let baseSize = CGSize(width: 300, height: 200)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

        // 1. With source frame within visible screen
        let source = CGRect(x: 200, y: 300, width: 300, height: 200)
        let frame1 = PinnedWindowState.initialFrame(baseSize: baseSize, sourceFrame: source, visibleScreenFrame: visible)
        #expect(frame1.origin == source.origin)
        #expect(frame1.size == baseSize)

        // 2. Without source frame -> centered
        let frame2 = PinnedWindowState.initialFrame(baseSize: baseSize, sourceFrame: nil, visibleScreenFrame: visible)
        #expect(frame2.midX == visible.midX)
        #expect(frame2.midY == visible.midY)
    }

    @Test @MainActor func panelPropertiesMatchSpec() {
        let panel = PinnedWindowPanel(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100))
        #expect(panel.isFloatingPanel)
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test @MainActor func managerPinsAndClosesMultipleWindows() {
        let screen = NSScreen.screens.first ?? NSScreen()
        let manager = PinnedWindowManager(screens: { [screen] })
        let image = Self.makeTestImage()

        var copies = 0
        var ocrs = 0
        let actions = PinnedWindowActions(
            copy: { copies += 1 },
            ocr: { ocrs += 1 }
        )

        let item1 = manager.pin(image: image, scale: 2.0, record: nil, sourceFrame: nil, actions: actions)
        let item2 = manager.pin(image: image, scale: 2.0, record: nil, sourceFrame: CGRect(x: 50, y: 50, width: 100, height: 50), actions: actions)

        #expect(manager.pinnedItems.count == 2)
        #expect(manager.pinnedItems.map(\.id) == [item1.id, item2.id])

        actions.copy()
        #expect(copies == 1)

        manager.close(id: item1.id)
        #expect(manager.pinnedItems.count == 1)
        #expect(manager.pinnedItems.first?.id == item2.id)

        manager.closeAll()
        #expect(manager.pinnedItems.isEmpty)
    }

    @Test @MainActor func closeRecordIDClosesMatchingAndPreservesNonMatching() {
        let screen = NSScreen.screens.first ?? NSScreen()
        let manager = PinnedWindowManager(screens: { [screen] })
        let image = Self.makeTestImage()
        let actions = PinnedWindowActions(copy: {}, ocr: {})

        let record1 = CaptureRecord(id: UUID(), fileName: "1.png", createdAt: .now, pixelWidth: 100, pixelHeight: 50, hasMarkup: false)
        let record2 = CaptureRecord(id: UUID(), fileName: "2.png", createdAt: .now, pixelWidth: 100, pixelHeight: 50, hasMarkup: false)

        let item1 = manager.pin(image: image, scale: 2.0, record: record1, sourceFrame: nil, actions: actions)
        let item2 = manager.pin(image: image, scale: 2.0, record: record1, sourceFrame: nil, actions: actions)
        let item3 = manager.pin(image: image, scale: 2.0, record: record2, sourceFrame: nil, actions: actions)
        let item4 = manager.pin(image: image, scale: 2.0, record: nil, sourceFrame: nil, actions: actions)

        #expect(manager.pinnedItems.count == 4)

        manager.close(recordID: record1.id)

        #expect(manager.pinnedItems.count == 2)
        #expect(!manager.pinnedItems.contains(where: { $0.id == item1.id }))
        #expect(!manager.pinnedItems.contains(where: { $0.id == item2.id }))
        #expect(manager.pinnedItems.contains(where: { $0.id == item3.id }))
        #expect(manager.pinnedItems.contains(where: { $0.id == item4.id }))
    }

    @Test @MainActor func contextMenuEditTriggersEditAndClosesPinnedWindow() throws {
        var editCount = 0
        var closeCount = 0
        let actions = PinnedWindowActions(
            copy: {},
            ocr: {},
            edit: { editCount += 1 }
        )
        let item = PinnedItem(recordID: nil, image: Self.makeTestImage(), scale: 2.0, sourceFrame: nil)
        let state = PinnedWindowState(baseSize: item.pointSize)
        let view = PinnedWindowView(item: item, state: state, actions: actions, onClose: { closeCount += 1 })

        let menu = try #require(view.menu(for: NSEvent()))
        let editItem = try #require(menu.items.first { $0.title == "Sửa ảnh…" })

        #expect(editItem.target === view)
        _ = editItem.target?.perform(editItem.action, with: editItem)

        #expect(closeCount == 1)
        #expect(editCount == 1)
    }
}
