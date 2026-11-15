import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

/// Stands in for ImageIO: makes blank pictures, counts how many are being made at once, and holds each one until the test lets it go.
nonisolated final class FakeThumbnailDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holding = true
    private var runningNow = 0
    private var peakNow = 0
    private var startedNames: [String] = []
    private var memoryBytes: [Data] = []
    private var fileSizes: [Int] = []
    /// The side, in pixels, of the pictures it makes.
    var side = 100
    /// What it answers for a picture it cannot read.
    var answersNil = false

    /// A test that fails half way must not leave decodes held for ever, which would hang the run instead of failing it: after five
    /// minutes everything is let through.
    init() {
        Task.detached { [self] in
            try? await Task.sleep(for: .seconds(300))
            letAllThrough()
        }
    }

    var running: Int { lock.withLock { runningNow } }
    /// How many are held, which is when `letHeldThrough` is sure to find them.
    var waiting: Int { lock.withLock { held.count } }
    var peak: Int { lock.withLock { peakNow } }
    var started: Int { lock.withLock { startedNames.count } }
    var names: [String] { lock.withLock { startedNames } }
    var memoryCalls: [Data] { lock.withLock { memoryBytes } }
    var sizesAsked: [Int] { lock.withLock { fileSizes } }

    /// Its decodes run on the main actor, where the test is, and not on the cooperative pool: the pool is shared with the heavy tests of
    /// this package, which can keep a decode from starting for a long time, and these tests count what is running.
    var decoder: ClipboardPreviewImageDecoder {
        ClipboardPreviewImageDecoder(
            file: { @MainActor [self] url, size in
                lock.withLock { fileSizes.append(size) }
                return await make(name: url.lastPathComponent)
            },
            memory: { @MainActor [self] data, _ in
                lock.withLock { memoryBytes.append(data) }
                return await make(name: "memory")
            }
        )
    }

    @MainActor private func make(name: String) async -> CGImage? {
        lock.withLock {
            runningNow += 1
            peakNow = max(peakNow, runningNow)
            startedNames.append(name)
        }
        await hold()
        lock.withLock { runningNow -= 1 }
        return answersNil ? nil : Self.picture(side: side)
    }

    private func hold() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let stay = lock.withLock { () -> Bool in
                if holding { held.append(continuation) }
                return holding
            }
            if !stay { continuation.resume() }
        }
    }

    /// From now on nothing is held, and what is held goes on.
    func letAllThrough() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { held = [] }
            return held
        }
        for continuation in waiting { continuation.resume() }
    }

    /// Lets the ones held so far go on, and holds the next.
    func letHeldThrough() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { held = [] }
            return held
        }
        for continuation in waiting { continuation.resume() }
    }

    static func picture(side: Int) -> CGImage? {
        CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}

/// How many pictures are decoded at once, which of them are kept, and what lets go of them: the budget the notch's tab, the floating
/// panel and the library share.
@Suite final class ClipboardThumbnailBudgetTests {
    let fake = FakeThumbnailDecoder()
    let directory = FileManager.default.temporaryDirectory.appending(path: "ClipboardThumbnailBudgetTests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        fake.letAllThrough()
        try? FileManager.default.removeItem(at: directory)
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

    func url(_ index: Int) -> URL {
        directory.appending(path: "picture-\(index).png")
    }

    func cache(limit: Int = ClipboardThumbnailCache.maxConcurrentDecodes) -> ClipboardThumbnailCache {
        ClipboardThumbnailCache(decoder: fake.decoder, decodeLimit: limit)
    }

    // MARK: How many at once

    @Test func theLimitIsFourAtOnce() {
        #expect(ClipboardThumbnailCache.maxConcurrentDecodes == 4)
    }

    @Test func atMostFourDecodesRunAtOnceWhateverNumberAskAndEveryOneIsAnswered() async {
        let cache = cache()
        var tasks: [Task<NSImage?, Never>] = []
        for index in 0..<20 { tasks.append(Task { await cache.thumbnail(for: url(index)) }) }

        #expect(await eventually { fake.running == 4 })
        // The others are waiting for a turn, not decoding.
        #expect(await eventually { cache.stats.waitingDecodes == 16 })
        #expect(fake.running == 4)
        #expect(fake.started == 4)

        fake.letAllThrough()
        for task in tasks { #expect(await task.value != nil) }

        #expect(fake.started == 20)
        #expect(fake.peak <= ClipboardThumbnailCache.maxConcurrentDecodes)
        #expect(cache.stats.peakConcurrentDecodes <= ClipboardThumbnailCache.maxConcurrentDecodes)
        #expect(cache.stats.decodesStarted == 20)
    }

    @Test func theLimitHoldsOverEveryHandleOnTheSameCache() async {
        let notch = cache()
        let library = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        let panel = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        var tasks: [Task<NSImage?, Never>] = []
        for index in 0..<24 {
            let handle = [notch, library, panel][index % 3]
            tasks.append(Task { await handle.thumbnail(for: url(index)) })
        }

        #expect(await eventually { fake.running == 4 })
        fake.letAllThrough()
        for task in tasks { _ = await task.value }

        #expect(fake.started == 24)
        #expect(fake.peak <= 4)
    }

    @Test func waitingRequestsAreDecodedInTheOrderTheyAsked() async {
        let cache = cache(limit: 1)
        var tasks = [Task { await cache.thumbnail(for: url(0)) }]
        #expect(await eventually { fake.waiting == 1 })
        for index in 1..<5 {
            tasks.append(Task { await cache.thumbnail(for: url(index)) })
            // One at a time into the line, so the order they asked in is known.
            #expect(await eventually { cache.stats.waitingDecodes == index })
        }

        // Each decode that finishes gives the turn to the one that has waited longest.
        for step in 1...5 {
            #expect(await eventually { fake.started == step && fake.waiting == 1 })
            fake.letHeldThrough()
        }
        // Whatever the steps found, nothing stays held.
        fake.letAllThrough()
        for task in tasks { _ = await task.value }

        #expect(fake.names == (0..<5).map { "picture-\($0).png" })
    }

    // MARK: Cards that scroll away

    @Test func aCardThatScrollsAwayBeforeItsTurnIsNeverDecoded() async {
        let cache = cache(limit: 2)
        var tasks: [Task<NSImage?, Never>] = []
        for index in 0..<8 { tasks.append(Task { await cache.thumbnail(for: url(index)) }) }
        // Which two got the turns is for the scheduler to say; what matters is that two are decoding and six wait.
        #expect(await eventually { fake.running == 2 && cache.stats.waitingDecodes == 6 })

        // All eight scroll away: the six that wait leave the line, the two that are decoding cannot be stopped.
        for task in tasks { task.cancel() }
        #expect(await eventually { cache.stats.waitingDecodes == 0 })
        fake.letAllThrough()
        var answers: [NSImage?] = []
        for task in tasks { answers.append(await task.value) }

        #expect(fake.started == 2)
        #expect(cache.stats.decodesStarted == 2)
        #expect(cache.stats.decodesSkipped == 6)
        #expect(answers.compactMap(\.self).count == 2)
        // What was decoded is kept, since it was made.
        #expect((0..<8).filter { cache.cachedThumbnail(for: url($0)) != nil }.count == 2)
    }

    @Test func afterManyCancelsTheNextRequestsStillRun() async {
        let cache = cache(limit: 2)
        var tasks: [Task<NSImage?, Never>] = []
        for index in 0..<40 { tasks.append(Task { await cache.thumbnail(for: url(index)) }) }
        #expect(await eventually { fake.running == 2 && cache.stats.waitingDecodes == 38 })
        for task in tasks { task.cancel() }
        #expect(await eventually { cache.stats.waitingDecodes == 0 })
        fake.letAllThrough()
        for task in tasks { _ = await task.value }
        #expect(fake.started == 2)

        // No slot was lost: a new card is decoded at once.
        let image = await cache.thumbnail(for: url(100))
        #expect(image != nil)
        #expect(fake.started == 3)
    }

    @Test func aSlotIsGivenBackWhenThePictureCannotBeRead() async {
        fake.answersNil = true
        fake.letAllThrough()
        let cache = cache(limit: 1)
        for index in 0..<5 { #expect(await cache.thumbnail(for: url(index)) == nil) }

        #expect(fake.started == 5)
        // Nothing of a picture that failed is kept, and the line is still open.
        fake.answersNil = false
        #expect(await cache.thumbnail(for: url(9)) != nil)
    }

    @Test func aPictureAnotherCardDecodedWhileThisOneWaitedIsNotDecodedAgain() async {
        let cache = cache(limit: 1)
        let first = Task { await cache.thumbnail(for: url(1)) }
        #expect(await eventually { fake.running == 1 })
        // Asks for the same picture while it is being decoded, and has to wait for the only turn.
        let second = Task { await cache.thumbnail(for: url(1)) }
        #expect(await eventually { cache.stats.waitingDecodes == 1 })

        fake.letAllThrough()
        let one = await first.value
        let two = await second.value

        #expect(fake.started == 1)
        #expect(one != nil && one === two)
    }

    // MARK: What is kept

    @Test func theBudgetIs24Megabytes() {
        #expect(ClipboardThumbnailStorage.costLimit == 24 * 1024 * 1024)
        #expect(cache().stats.cachedBytes == 0)
    }

    @Test func whatIsKeptStaysInTheBudgetPlusTheLatestFew() async {
        fake.side = 400
        fake.letAllThrough()
        let cache = cache()
        // 400 x 400 pixels at four bytes: 640 000 bytes each, so a hundred of them are about 61 MB.
        for index in 0..<100 { _ = await cache.thumbnail(for: url(index)) }

        let stats = cache.stats
        #expect(stats.cachedBytes <= ClipboardThumbnailStorage.costLimit)
        #expect(stats.cachedCount < 100)
        #expect(stats.recentCount == ClipboardThumbnailStorage.recentLimit)
        // The latest are always there, kept or not by the cache.
        #expect(cache.cachedThumbnail(for: url(99)) != nil)
    }

    @Test func aThumbnailIsMadeOnceAndKeptBySize() async {
        fake.letAllThrough()
        let cache = cache()
        let file = url(1)
        let notch = await cache.thumbnail(for: file)
        let glyph = await cache.thumbnail(for: file, maxPixelSize: ClipboardThumbnailCache.glyphPixelSize)
        _ = await cache.thumbnail(for: file)
        _ = await cache.thumbnail(for: file, maxPixelSize: ClipboardThumbnailCache.glyphPixelSize)

        #expect(notch != nil && glyph != nil && notch !== glyph)
        #expect(fake.sizesAsked == [ClipboardThumbnailCache.defaultPixelSize, ClipboardThumbnailCache.glyphPixelSize])
        #expect(cache.cachedThumbnail(for: file) === notch)
        #expect(cache.cachedThumbnail(for: file, maxPixelSize: ClipboardThumbnailCache.glyphPixelSize) === glyph)
        #expect(cache.cachedThumbnail(for: file, maxPixelSize: 500) == nil)
    }

    @Test func eachHandleAsksForItsOwnSizeOfTheSameFile() async {
        fake.letAllThrough()
        let notch = cache()
        let library = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        _ = await notch.thumbnail(for: url(1))
        _ = await library.thumbnail(for: url(1))

        #expect(fake.sizesAsked == [240, 200])
        // One budget: what the library decoded is there for any handle that asks for that size.
        #expect(notch.cachedThumbnail(for: url(1), maxPixelSize: 200) === library.cachedThumbnail(for: url(1)))
    }

    // MARK: Letting go

    @Test func aClosedWindowTakesItsOwnSizesAndLeavesTheOthers() async {
        fake.letAllThrough()
        let notch = cache()
        let library = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        // Nine pictures in all, so every one is among the twelve latest, which are held whatever `NSCache` does.
        for index in 0..<3 {
            _ = await notch.thumbnail(for: url(index))
            _ = await library.thumbnail(for: url(index))
            _ = await library.thumbnail(for: url(index), maxPixelSize: ClipboardThumbnailCache.glyphPixelSize)
        }

        library.release()

        for index in 0..<3 {
            #expect(notch.cachedThumbnail(for: url(index)) != nil, "the notch's own stays")
            #expect(library.cachedThumbnail(for: url(index)) == nil, "the library's goes")
            #expect(library.cachedThumbnail(for: url(index), maxPixelSize: ClipboardThumbnailCache.glyphPixelSize) == nil)
        }
        // Of the nine, the three that were the notch's.
        #expect(notch.stats.recentCount == 3)
    }

    @Test func aSizeAnotherOpenWindowStillUsesIsKeptUntilTheLastOneCloses() async {
        fake.letAllThrough()
        let notch = cache()
        let library = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        let panel = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        _ = await library.thumbnail(for: url(1))
        _ = await panel.thumbnail(for: url(2))

        library.release()
        #expect(panel.cachedThumbnail(for: url(1)) != nil, "the panel is open and uses the same size")
        #expect(panel.cachedThumbnail(for: url(2)) != nil)

        panel.release()
        #expect(panel.cachedThumbnail(for: url(1)) == nil)
        #expect(panel.cachedThumbnail(for: url(2)) == nil)
    }

    @Test func aHandleThatLetGoAndIsUsedAgainTakesItsSizeUpAgain() async {
        fake.letAllThrough()
        let notch = cache()
        let library = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        _ = await library.thumbnail(for: url(1))
        library.release()
        #expect(library.cachedThumbnail(for: url(1)) == nil)

        _ = await library.thumbnail(for: url(1))
        let other = ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: notch)
        other.release()
        #expect(library.cachedThumbnail(for: url(1)) != nil, "the library is open again: another handle closing does not take its size")
    }

    @Test func theSystemBeingShortOfMemoryForgetsEverythingEvenTheLatest() async {
        fake.letAllThrough()
        let cache = cache()
        for index in 0..<5 { _ = await cache.thumbnail(for: url(index)) }
        #expect(cache.stats.recentCount == 5)

        cache.releaseMemory()

        for index in 0..<5 { #expect(cache.cachedThumbnail(for: url(index)) == nil) }
        let stats = cache.stats
        #expect(stats.cachedCount == 0 && stats.cachedBytes == 0 && stats.recentCount == 0)
        #expect(stats.memoryReleases == 1)
        // They come back as cards ask.
        #expect(await cache.thumbnail(for: url(1)) != nil)
    }

    @Test func memoryBeingShortDoesNotThrowAwayADecodeThatIsOnItsWay() async {
        let cache = cache()
        let task = Task { await cache.thumbnail(for: url(1)) }
        #expect(await eventually { fake.running == 1 })

        cache.releaseMemory()
        fake.letAllThrough()

        // The card on screen is waiting for exactly this picture.
        #expect(await task.value != nil)
        #expect(cache.cachedThumbnail(for: url(1)) != nil)
    }

    @Test func theSystemEmptyingTheCacheItselfLeavesTheLatestAndRemovesAllForgetsThemToo() async {
        fake.letAllThrough()
        let cache = cache()
        let first = await cache.thumbnail(for: url(1))

        cache.simulateMemoryPressurePurge()
        #expect(cache.cachedThumbnail(for: url(1)) === first)

        cache.removeAll()
        #expect(cache.cachedThumbnail(for: url(1)) == nil)
        #expect(cache.stats.recentCount == 0)
    }

    // MARK: A board that locks

    @Test func aPictureInAFileThatIsBeingDecodedWhenTheCacheIsEmptiedIsStillGivenToItsCard() async {
        let cache = cache()
        let task = Task { await cache.thumbnail(for: url(1)) }
        #expect(await eventually { fake.running == 1 })

        // A board locked elsewhere: a picture in a file belongs to no lock, so the card that waits for it is not left with a placeholder.
        cache.removeAll()
        fake.letAllThrough()

        #expect(await task.value != nil)
    }

    @Test func aPictureInMemoryIsReadOnlyWhenItGetsItsTurnNotWhenItWasAsked() async {
        let openImages = ClipboardOpenImages()
        let board = UUID()
        openImages.add(Data("before".utf8), named: "secret.png", to: board)
        let cache = cache(limit: 1)
        cache.openImages = openImages
        let blocker = Task { await cache.thumbnail(for: url(1)) }
        #expect(await eventually { fake.running == 1 })

        let memory = Task { await cache.thumbnail(for: ClipboardOpenImages.url(forFileName: "secret.png")) }
        #expect(await eventually { cache.stats.waitingDecodes == 1 })
        // Waiting: nothing of the picture was read yet.
        #expect(fake.memoryCalls.isEmpty)
        openImages.add(Data("after".utf8), named: "secret.png", to: board)

        fake.letAllThrough()
        _ = await blocker.value
        _ = await memory.value

        #expect(fake.memoryCalls == [Data("after".utf8)])
    }

    @Test func aPictureWaitingForItsTurnWhenItsBoardLocksIsNeverReadOrDecoded() async {
        let openImages = ClipboardOpenImages()
        let board = UUID()
        openImages.add(Data("secret".utf8), named: "secret.png", to: board)
        let cache = cache(limit: 1)
        cache.openImages = openImages
        let blocker = Task { await cache.thumbnail(for: url(1)) }
        #expect(await eventually { fake.running == 1 })
        let memory = Task { await cache.thumbnail(for: ClipboardOpenImages.url(forFileName: "secret.png")) }
        #expect(await eventually { cache.stats.waitingDecodes == 1 })

        // The board locks: its pictures leave memory and the thumbnails are forgotten.
        openImages.remove(board: board)
        cache.removeAll()
        fake.letAllThrough()
        _ = await blocker.value

        #expect(await memory.value == nil)
        #expect(fake.memoryCalls.isEmpty, "the decoder was never given the bytes")
        #expect(cache.cachedThumbnail(for: ClipboardOpenImages.url(forFileName: "secret.png")) == nil)
    }

    @Test func aPictureInMemoryBeingDecodedWhenItsBoardLocksIsNotKept() async {
        let openImages = ClipboardOpenImages()
        let board = UUID()
        openImages.add(Data("secret".utf8), named: "secret.png", to: board)
        let cache = cache()
        cache.openImages = openImages
        let address = ClipboardOpenImages.url(forFileName: "secret.png")
        let task = Task { await cache.thumbnail(for: address) }
        #expect(await eventually { fake.running == 1 })
        #expect(fake.memoryCalls.count == 1)

        openImages.remove(board: board)
        cache.removeAll()
        fake.letAllThrough()

        #expect(await task.value == nil)
        #expect(cache.cachedThumbnail(for: address) == nil)
        #expect(cache.stats.cachedCount == 0)
    }

    @Test func aPictureInMemoryThatAnotherOpenBoardStillHoldsIsKeptWhenOneBoardLocks() async {
        let openImages = ClipboardOpenImages()
        let locking = UUID(), staying = UUID()
        openImages.add(Data("shared".utf8), named: "shared.png", to: locking)
        openImages.add(Data("shared".utf8), named: "shared.png", to: staying)
        let cache = cache()
        cache.openImages = openImages
        let address = ClipboardOpenImages.url(forFileName: "shared.png")
        let task = Task { await cache.thumbnail(for: address) }
        #expect(await eventually { fake.running == 1 })

        // One of the two boards that hold the picture locks: it is still on screen in the other, whose card waits for it.
        openImages.remove(board: locking)
        cache.removeAll()
        fake.letAllThrough()

        #expect(await task.value != nil)
        #expect(cache.cachedThumbnail(for: address) != nil)
    }

    // MARK: Counters

    @Test func theCountersSayWhatHappenedWithoutNamingAnything() async {
        fake.letAllThrough()
        let cache = cache(limit: 2)
        for index in 0..<3 { _ = await cache.thumbnail(for: url(index)) }
        _ = await cache.thumbnail(for: url(0))

        let stats = cache.stats
        #expect(stats.decodesStarted == 3)
        #expect(stats.decodesSkipped == 0)
        // `NSCache` may let go of what it holds at any moment when the machine is short of memory, so it is only bounded from above;
        // the latest are held by the cache itself.
        #expect(stats.recentCount == 3)
        let picture = FakeThumbnailDecoder.picture(side: 100)
        #expect(stats.cachedCount <= 3)
        #expect(stats.cachedBytes <= 3 * (picture?.bytesPerRow ?? 0) * 100)
        #expect(stats.peakConcurrentDecodes >= 1)
    }

    @Test func recentLimitHoldsAFullSmallGridScreenfulOfFortyEightCards() async {
        // 800 x 800 x 4 = 2.56 MB per thumbnail, so 48 cards (>117 MB) exceed costLimit and test `recent` retention across evictions.
        fake.side = 800
        fake.letAllThrough()
        let cache = cache()
        for index in 0..<48 { _ = await cache.thumbnail(for: url(index)) }

        #expect(ClipboardThumbnailStorage.recentLimit == 48)
        for index in 0..<48 { #expect(cache.cachedThumbnail(for: url(index)) != nil) }
        #expect(fake.started == 48)
    }
}
