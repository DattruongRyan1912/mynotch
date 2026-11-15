import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ClipboardModule

/// A card asks for its link's page only after it has stayed on screen for a moment, and only a link's card asks.
@Suite final class ClipboardLinkPreviewTriggerTests {
    let fixture = OptionalFeaturesFixture()
    let url = "https://www.example.com/the-hien"
    var windows: [NSWindow] = []

    func closeWindows() {
        windows.forEach { $0.contentView = nil }
        windows = []
    }

    func show(_ item: ClipboardItem) -> NSWindow {
        let host = NSHostingView(rootView: Color.clear.frame(width: 40, height: 40).requestsLinkPreview(of: item, from: fixture.module))
        host.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        windows.append(window)
        return window
    }

    @Test func aLinkCardThatStaysIsRead() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        fixture.module.linkPreviewDwell = .milliseconds(150)
        fixture.copy(url)
        _ = show(try fixture.item(url))
        // Not at once: the card has to stay.
        #expect(fixture.transport.requests.isEmpty)
        await fixture.wait { !fixture.transport.requests.isEmpty }
        await fixture.waitForLinks()
        #expect(fixture.transport.requestedURLs.first == url)
        #expect(try fixture.item(url).linkPreview?.title == "Trang thử")
        closeWindows()
    }

    @Test func aCardThatIsOnlyScrolledPastReadsNothing() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        // A moment so long that nothing but the card going away can end it, however long something else keeps the main actor.
        fixture.module.linkPreviewDwell = .seconds(30)
        fixture.copy(url)
        let window = show(try fixture.item(url))
        // Shown, and not read: the moment has not passed.
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.transport.requests.isEmpty)
        // Gone before it does.
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.transport.requests.isEmpty)
        #expect(fixture.module.linkPreviews.startedCount == 0)
        closeWindows()
    }

    @Test func aCardOfAnotherKindAsksForNothing() async throws {
        try fixture.setLinkPreviews(true)
        await fixture.start()
        fixture.module.linkPreviewDwell = .milliseconds(20)
        fixture.copy("chỉ là chữ")
        _ = show(try fixture.item("chỉ là chữ"))
        try await Task.sleep(for: .milliseconds(300))
        #expect(fixture.transport.requests.isEmpty)
        closeWindows()
    }

    @Test func theMomentIsShort() {
        #expect(ClipboardModule.defaultLinkPreviewDwell == .milliseconds(400))
        #expect(fixture.module.linkPreviewDwell == ClipboardModule.defaultLinkPreviewDwell)
    }
}
