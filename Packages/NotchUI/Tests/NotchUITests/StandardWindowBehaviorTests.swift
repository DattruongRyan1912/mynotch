import AppKit
import Testing
@testable import NotchUI

@Suite
@MainActor
struct StandardWindowBehaviorTests {

    // WB-1: Happy - apply(to:, allowsNativeFullScreen: true) sets [.fullScreenPrimary] and normal level
    @Test
    func test_WB1_apply_allowsNativeFullScreen_setsFullScreenPrimary() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = true

        StandardWindowBehavior.apply(to: window, allowsNativeFullScreen: true)

        #expect(window.level == .normal)
        #expect(window.collectionBehavior == [.fullScreenPrimary])
        #expect(window.hidesOnDeactivate == false)
        #expect(!window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!window.collectionBehavior.contains(.stationary))
    }

    // WB-2: Regression - default apply(to:) sets empty collectionBehavior []
    @Test
    func test_WB2_apply_default_setsEmptyCollectionBehavior() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = true

        StandardWindowBehavior.apply(to: window)

        #expect(window.level == .normal)
        #expect(window.collectionBehavior == [])
        #expect(window.hidesOnDeactivate == false)
    }

    // WB-3: Edge - Idempotent and can transition between true and false
    @Test
    func test_WB3_apply_idempotentAndTransition() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(width: 880, height: 560)
        window.isOpaque = false
        window.backgroundColor = .clear

        // Apply true twice
        StandardWindowBehavior.apply(to: window, allowsNativeFullScreen: true)
        #expect(window.collectionBehavior == [.fullScreenPrimary])
        StandardWindowBehavior.apply(to: window, allowsNativeFullScreen: true)
        #expect(window.collectionBehavior == [.fullScreenPrimary])

        // Transition back to false
        StandardWindowBehavior.apply(to: window, allowsNativeFullScreen: false)
        #expect(window.collectionBehavior == [])

        // Window style and geometry properties preserved
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.isOpaque == false)
        #expect(window.backgroundColor == .clear)
        #expect(window.contentMinSize == NSSize(width: 880, height: 560))
    }

    @Test
    func test_applyStandardBehavior_setsNormalLevel() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = true

        StandardWindowBehavior.apply(to: window)

        #expect(window.level == .normal)
        #expect(!window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!window.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!window.collectionBehavior.contains(.stationary))
        #expect(window.collectionBehavior == [])
        #expect(window.hidesOnDeactivate == false)
    }

    @Test
    func test_apply_isIdempotent() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        StandardWindowBehavior.apply(to: window)
        let level1 = window.level
        let behavior1 = window.collectionBehavior
        let hides1 = window.hidesOnDeactivate

        StandardWindowBehavior.apply(to: window)
        #expect(window.level == level1)
        #expect(window.collectionBehavior == behavior1)
        #expect(window.hidesOnDeactivate == hides1)
    }
}
