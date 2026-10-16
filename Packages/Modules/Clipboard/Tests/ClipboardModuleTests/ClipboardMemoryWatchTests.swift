import CoreGraphics
import Dispatch
import Foundation
import ImageIO
import Testing
@testable import ClipboardModule

/// A source of memory pressure the test fires by hand. Real pressure is the whole machine's, so nothing here ever causes any.
final class FakeMemoryPressure {
    private(set) var started = 0
    private(set) var stopped = 0
    private var handler: (@MainActor @Sendable (ClipboardMemoryPressure.Level) -> Void)?

    var pressure: ClipboardMemoryPressure {
        ClipboardMemoryPressure(
            start: { [self] handler in
                started += 1
                self.handler = handler
                return "token-\(started)"
            },
            stop: { [self] token in
                #expect(token as? String == "token-\(started)")
                stopped += 1
                handler = nil
            }
        )
    }

    var isListening: Bool { handler != nil }

    func fire(_ level: ClipboardMemoryPressure.Level) {
        handler?(level)
    }
}

@Suite struct ClipboardMemoryWatchTests {
    @Test func theWatchListensFromStartUntilStop() {
        let fake = FakeMemoryPressure()
        let watch = ClipboardMemoryWatch()
        watch.pressure = fake.pressure
        #expect(!watch.isWatching)

        var levels: [ClipboardMemoryPressure.Level] = []
        watch.start { levels.append($0) }
        #expect(watch.isWatching && fake.started == 1)
        fake.fire(.warning)
        fake.fire(.critical)
        #expect(levels == [.warning, .critical])

        watch.stop()
        #expect(!watch.isWatching && fake.stopped == 1)
        // Nothing reaches a handler that was stopped, and stopping twice stops once.
        fake.fire(.critical)
        watch.stop()
        #expect(levels.count == 2 && fake.stopped == 1)
    }

    @Test func startingAgainStopsTheListenerThatWasThere() {
        let fake = FakeMemoryPressure()
        let watch = ClipboardMemoryWatch()
        watch.pressure = fake.pressure
        watch.start { _ in }
        watch.start { _ in }
        #expect(fake.started == 2 && fake.stopped == 1)
        watch.stop()
        #expect(fake.stopped == 2)
    }

    /// The real source, made and cancelled at once: no event is ever delivered to it.
    @Test func theSystemSourceListensForWarningAndCriticalOnTheMainQueueAndCancels() throws {
        let token = ClipboardMemoryPressure.system.start { _ in }
        let source = try #require(token as? any DispatchSourceMemoryPressure)
        #expect(!source.isCancelled)

        ClipboardMemoryPressure.system.stop(token)

        #expect(source.isCancelled)
    }
}

extension ClipboardModuleTests {
    /// A picture on disk for the thumbnails to read.
    private func memoryPicture(named name: String) throws -> URL {
        let folder = temporaryRoot.appending(path: "memory-pictures")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        let context = try #require(CGContext(
            data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func theModuleListensForMemoryPressureOnlyWhileItRuns() async {
        let fake = FakeMemoryPressure()
        module.memoryWatch.pressure = fake.pressure
        #expect(fake.started == 0)

        await start()
        #expect(fake.started == 1 && fake.isListening)

        await harness.registry.setEnabled(false, for: "clipboard")
        #expect(fake.stopped == 1 && !fake.isListening)

        await harness.registry.setEnabled(true, for: "clipboard")
        #expect(fake.started == 2 && fake.isListening)
    }

    @Test func aWarningOrACriticalLevelLetsGoOfEveryThumbnailEvenTheLatest() async throws {
        let fake = FakeMemoryPressure()
        module.memoryWatch.pressure = fake.pressure
        await start()
        let url = try memoryPicture(named: "pressure.png")

        for (round, level) in [ClipboardMemoryPressure.Level.warning, .critical].enumerated() {
            _ = await module.thumbnails.thumbnail(for: url)
            let library = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: module.thumbnails)
            _ = await library.thumbnail(for: url)
            #expect(module.thumbnails.cachedThumbnail(for: url) != nil)
            #expect(module.thumbnails.stats.recentCount == 2)

            fake.fire(level)

            #expect(module.thumbnails.cachedThumbnail(for: url) == nil, "\(level)")
            #expect(library.cachedThumbnail(for: url) == nil, "\(level)")
            #expect(module.thumbnails.stats.recentCount == 0, "the latest are let go too")
            #expect(module.thumbnails.stats.memoryReleases == round + 1)
        }
    }

    @Test func pressureAfterTheModuleStoppedReachesNothing() async throws {
        let fake = FakeMemoryPressure()
        module.memoryWatch.pressure = fake.pressure
        await start()
        await harness.registry.setEnabled(false, for: "clipboard")
        let before = module.thumbnails.stats.memoryReleases

        fake.fire(.critical)

        #expect(module.thumbnails.stats.memoryReleases == before)
    }
}
