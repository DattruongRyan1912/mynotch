import AppKit
import SwiftUI
import Testing
@testable import ClipboardModule

/// What the views ask the cache for: each slot its own size, never more than it can show, and nothing once the view is gone. The views
/// are hosted in a window that is never put on a screen, and the decodes are the fake's.
@Suite final class ClipboardThumbnailViewTests {
    let fake = FakeThumbnailDecoder()
    var windows: [NSWindow] = []
    let url = URL(fileURLWithPath: "/tmp/mynotch-thumbnail-view-test/\(UUID().uuidString).png")

    deinit {
        fake.letAllThrough()
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        // By the clock, not by the count: the cooperative pool is shared with the heavy tests of this package, which can keep a decode
        // from starting for many seconds.
        let deadline = ContinuousClock.now + .seconds(240)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    var item: ClipboardItem {
        ClipboardItem(id: UUID(), content: ClipboardModuleTests.image("view"), contentHash: "h", copiedAt: .now)
    }

    @discardableResult
    func show(_ view: some View) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view.frame(width: 150, height: 110)))
        host.frame = CGRect(x: 0, y: 0, width: 150, height: 110)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        windows.append(window)
        return host
    }

    @Test func aListRowsPictureAsksForTheSmallSizeOnly() async {
        fake.letAllThrough()
        let cache = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, decoder: fake.decoder)
        show(ClipboardItemGlyph(item: item, imageURL: url, thumbnails: cache))

        #expect(await eventually { cache.cachedThumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.glyphPixelSize) != nil })
        #expect(fake.sizesAsked == [ClipboardThumbnailCache.glyphPixelSize])
        #expect(cache.cachedThumbnail(for: url) == nil)
    }

    @Test func aLinksPictureInARowAsksForTheSmallSizeToo() async {
        fake.letAllThrough()
        let cache = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, decoder: fake.decoder)
        let link = ClipboardItem(id: UUID(), content: .link(URL(string: "https://example.com")!), contentHash: "l", copiedAt: .now)
        show(ClipboardItemGlyph(item: link, imageURL: nil, thumbnails: cache, link: ClipboardLinkPreviewDisplay(title: nil, imageURL: url)))

        #expect(await eventually { cache.cachedThumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.glyphPixelSize) != nil })
        #expect(fake.sizesAsked == [ClipboardThumbnailCache.glyphPixelSize])
    }

    @Test func aCardAsksForTheSizeOfItsCache() async {
        fake.letAllThrough()
        let notch = ClipboardThumbnailCache(decoder: fake.decoder)
        let library = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        show(ClipboardContentPreview(content: ClipboardModuleTests.image("card"), imageURL: url, thumbnails: notch, style: .notch(onGlass: false)))
        show(ClipboardContentPreview(content: ClipboardModuleTests.image("card"), imageURL: url, thumbnails: library, style: .library(.medium)))

        #expect(await eventually { fake.started == 2 })
        #expect(Set(fake.sizesAsked) == [ClipboardThumbnailCache.defaultPixelSize, ClipboardThumbnailCache.libraryPixelSize])
    }

    @Test func changingTheLibrarysCardSizeDoesNotDecodeTheCardsAgain() async {
        fake.letAllThrough()
        let cache = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, decoder: fake.decoder)
        let content = ClipboardModuleTests.image("slider")
        let host = show(ClipboardContentPreview(content: content, imageURL: url, thumbnails: cache, style: .library(.small)))
        #expect(await eventually { cache.cachedThumbnail(for: url) != nil })

        // The slider moves: the same card, in a larger style.
        for size in [ClipboardLibraryCardSize.medium, .large, .small] {
            host.rootView = AnyView(
                ClipboardContentPreview(content: content, imageURL: url, thumbnails: cache, style: .library(size)).frame(width: 150, height: 110)
            )
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(30))
        }

        #expect(fake.started == 1)
    }

    @Test func aCardThatLeavesTheScreenBeforeItsTurnIsNeverDecoded() async {
        let cache = ClipboardThumbnailCache(decoder: fake.decoder, decodeLimit: 1)
        let blocker = Task { await cache.thumbnail(for: URL(fileURLWithPath: "/tmp/mynotch-blocker.png")) }
        #expect(await eventually { fake.waiting == 1 })
        show(ClipboardContentPreview(content: ClipboardModuleTests.image("gone"), imageURL: url, thumbnails: cache, style: .notch(onGlass: false)))
        #expect(await eventually { cache.stats.waitingDecodes == 1 })

        // The card scrolls out of the lazy row: its view goes, and so does its place in the line.
        windows.removeAll { $0.contentView = nil; return true }
        #expect(await eventually { cache.stats.waitingDecodes == 0 })

        fake.letAllThrough()
        _ = await blocker.value
        #expect(fake.started == 1)
        #expect(cache.stats.decodesSkipped == 1)
    }

    @Test func aCardWhoseThumbnailIsAlreadyCachedShowsItWithoutDecodingAgainAndRecordsItsHandleUse() async {
        fake.letAllThrough()
        let notch = ClipboardThumbnailCache(decoder: fake.decoder)
        let library = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        _ = await notch.thumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.glyphPixelSize)

        show(ClipboardItemGlyph(item: item, imageURL: url, thumbnails: library))
        try? await Task.sleep(for: .milliseconds(30))
        notch.release()

        #expect(fake.started == 1)
        #expect(library.cachedThumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.glyphPixelSize) != nil)

        library.release()
        #expect(library.cachedThumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.glyphPixelSize) == nil)
    }
}
