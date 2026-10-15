import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

/// How large a picture is decoded for the preview: at the size it is drawn, never more than the picture has, never more than a
/// bound, and from memory or a file with the same ImageIO call the thumbnails use. Pictures are made in memory; no file is written.
@Suite struct ClipboardPreviewImageTests {
    typealias Preview = ClipboardPreviewImage

    /// A solid PNG of the given pixel size, as bytes.
    static func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    // MARK: The size asked for

    @Test func aBigPictureIsDecodedAtTheSizeItIsDrawnAt() {
        // Fitted into 1000 x 700 points on a 2x screen, 4000 x 3000 is drawn at 1867 x 1400 pixels.
        let size = Preview.maxPixelSize(display: CGSize(width: 1000, height: 700), scale: 2, pixelWidth: 4000, pixelHeight: 3000)
        #expect(size == 1867)
    }

    @Test func aPortraitPictureIsFittedByItsHeight() {
        let size = Preview.maxPixelSize(display: CGSize(width: 1000, height: 700), scale: 2, pixelWidth: 3000, pixelHeight: 4000)
        #expect(size == 1400)
    }

    @Test func aSmallPictureIsNeverAskedToBeLarger() {
        let size = Preview.maxPixelSize(display: CGSize(width: 1000, height: 700), scale: 2, pixelWidth: 100, pixelHeight: 50)
        #expect(size == 100)
    }

    @Test func aHugePictureIsBoundedWhateverTheScreen() {
        let size = Preview.maxPixelSize(display: CGSize(width: 5000, height: 3000), scale: 2, pixelWidth: 20000, pixelHeight: 10000)
        #expect(size == Preview.pixelCap)
        #expect(Preview.pixelCap >= 4096 && Preview.pixelCap <= 8192)
    }

    @Test func aSharperScreenAsksForMorePixelsButNotMoreThanThePictureHas() {
        let one = Preview.maxPixelSize(display: CGSize(width: 800, height: 600), scale: 1, pixelWidth: 3000, pixelHeight: 2000)
        let two = Preview.maxPixelSize(display: CGSize(width: 800, height: 600), scale: 2, pixelWidth: 3000, pixelHeight: 2000)
        let three = Preview.maxPixelSize(display: CGSize(width: 800, height: 600), scale: 3, pixelWidth: 3000, pixelHeight: 2000)
        #expect(one < two)
        #expect(two < three)
        #expect(three <= 3000)
    }

    @Test func aPictureWhoseSizeIsNotKnownIsBoundedByTheDisplayAndTheCap() {
        let size = Preview.maxPixelSize(display: CGSize(width: 1000, height: 700), scale: 2, pixelWidth: 0, pixelHeight: 0)
        #expect(size == 2000)
        #expect(Preview.maxPixelSize(display: CGSize(width: 9000, height: 9000), scale: 2, pixelWidth: 0, pixelHeight: 0) == Preview.pixelCap)
    }

    @Test func aDisplayThatHasNoSizeYetStillGivesAUsableBound() {
        let size = Preview.maxPixelSize(display: .zero, scale: 2, pixelWidth: 4000, pixelHeight: 3000)
        #expect(size >= 1 && size <= Preview.pixelCap)
    }

    // MARK: Decoding

    @Test func aPictureInMemoryIsDecodedNoLargerThanAskedAndKeepsItsShape() async throws {
        let data = try Self.png(width: 3000, height: 2000)
        let image = try #require(await Preview.load(.memory(data), maxPixelSize: 500))
        #expect(image.width == 500)
        #expect(image.height == 333)
    }

    @Test func aPictureSmallerThanTheBoundIsNotEnlarged() async throws {
        let data = try Self.png(width: 100, height: 50)
        let image = try #require(await Preview.load(.memory(data), maxPixelSize: 4000))
        #expect(image.width == 100)
        #expect(image.height == 50)
    }

    @Test func theBoundHoldsForEveryShape() async throws {
        for (width, height) in [(4000, 100), (100, 4000), (2048, 2048), (1, 3000)] {
            let image = try #require(await Preview.load(.memory(try Self.png(width: width, height: height)), maxPixelSize: 640))
            #expect(max(image.width, image.height) <= 640, "\(width) x \(height)")
        }
    }

    @Test func bytesThatAreNotAPictureOrAFileThatIsNotThereGiveNothing() async {
        #expect(await Preview.load(.memory(Data("not a png".utf8)), maxPixelSize: 500) == nil)
        #expect(await Preview.load(.memory(Data()), maxPixelSize: 500) == nil)
        let missing = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString).png")
        #expect(await Preview.load(.file(missing), maxPixelSize: 500) == nil)
    }

    // MARK: Fast scrolling

    /// Counts the decodes asked of it, from whichever thread they come.
    final class FakeDecoder: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private(set) var sizes: [Int] = []

        var calls: Int { lock.withLock { count } }

        var decoder: ClipboardPreviewImageDecoder {
            ClipboardPreviewImageDecoder(
                file: { [self] _, size in await decode(size) },
                memory: { [self] _, size in await decode(size) }
            )
        }

        private func decode(_ size: Int) async -> CGImage? {
            lock.withLock {
                count += 1
                sizes.append(size)
            }
            return CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }

    @Test func aTaskThatWasCancelledNeverStartsTheDecode() async {
        let fake = FakeDecoder()
        let task = Task { await Preview.load(.memory(Data("x".utf8)), maxPixelSize: 100, decoder: fake.decoder) }
        task.cancel()
        #expect(await task.value == nil)
        #expect(fake.calls == 0)

        let file = Task { await Preview.load(.file(URL(fileURLWithPath: "/tmp/none.png")), maxPixelSize: 100, decoder: fake.decoder) }
        file.cancel()
        #expect(await file.value == nil)
        #expect(fake.calls == 0)
    }

    @Test func aTaskThatIsNotCancelledDecodesOnceAtTheSizeAsked() async {
        let fake = FakeDecoder()
        #expect(await Preview.load(.memory(Data("x".utf8)), maxPixelSize: 640, decoder: fake.decoder) != nil)
        #expect(await Preview.load(.file(URL(fileURLWithPath: "/tmp/none.png")), maxPixelSize: 320, decoder: fake.decoder) != nil)
        #expect(fake.sizes == [640, 320])
    }

    /// Stands in for the pause: every task that sleeps in it waits until the test lets it go or the task is cancelled, as a real sleep
    /// would be cut short, so the test needs no clock.
    nonisolated final class PauseGate: @unchecked Sendable {
        private let lock = NSLock()
        private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
        private var cancelledBeforeWaiting: Set<UUID> = []

        var waiting: Int { lock.withLock { waiters.count } }

        func sleep(_ pause: Duration) async {
            let id = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let early = lock.withLock { () -> Bool in
                        if cancelledBeforeWaiting.remove(id) != nil { return true }
                        waiters[id] = continuation
                        return false
                    }
                    if early { continuation.resume() }
                }
            } onCancel: {
                let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                    if let waiting = waiters.removeValue(forKey: id) { return waiting }
                    cancelledBeforeWaiting.insert(id)
                    return nil
                }
                continuation?.resume()
            }
        }

        /// The pause is over for everyone still in it.
        func releaseAll() {
            let all = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                defer { waiters = [:] }
                return Array(waiters.values)
            }
            for continuation in all { continuation.resume() }
        }
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<2000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Holding ↓ over big pictures: each one is selected for a moment and then replaced, so only the one the user stops on is decoded.
    /// The earlier ones are all waiting out the pause (they have started) when they are cancelled, which is what the wait is for.
    @Test func holdingTheArrowDecodesOnlyThePictureTheUserStopsOn() async {
        let fake = FakeDecoder()
        let gate = PauseGate()
        let tasks = (0..<6).map { _ in
            Task { await Preview.loadAfterPause(.memory(Data("x".utf8)), maxPixelSize: 100, sleep: { await gate.sleep($0) }, decoder: fake.decoder) }
        }
        #expect(await eventually { gate.waiting == 6 })

        // The next picture comes before the pause is over: the views of the earlier ones go, and their tasks are cancelled.
        for task in tasks.dropLast() { task.cancel() }
        for task in tasks.dropLast() { #expect(await task.value == nil) }
        #expect(fake.calls == 0)

        // The last one stays, and its pause ends.
        gate.releaseAll()
        #expect(await tasks[5].value != nil)
        #expect(fake.calls == 1)
    }

    @Test func aPictureThatStaysIsDecodedOnceAfterThePause() async {
        let fake = FakeDecoder()
        #expect(await Preview.loadAfterPause(.memory(Data("x".utf8)), maxPixelSize: 100, pause: .milliseconds(5), decoder: fake.decoder) != nil)
        #expect(fake.calls == 1)
    }

    @Test func thePanesPauseIsShortEnoughToFeelInstantAndLongEnoughToSkipPictures() {
        #expect(Preview.pause == .milliseconds(80))
    }
}
