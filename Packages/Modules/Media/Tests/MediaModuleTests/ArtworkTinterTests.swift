import Foundation
import Testing
@testable import MediaModule

/// Stands in for the background extraction: records what it was asked, can hold an answer until the test lets it go, and says
/// whether it ran on the main thread.
nonisolated final class FakeExtractor: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Data] = []
    private var finished = 0
    private var held: Set<Data> = []
    private var released: Set<Data> = []
    private var waiting: [Data: CheckedContinuation<Void, Never>] = [:]
    private var ranOnMainThread = false
    /// What each cover gives; a cover not listed here gives nothing.
    private var answers: [Data: ArtworkPalette] = [:]

    var callCount: Int { lock.withLock { calls.count } }
    var finishedCount: Int { lock.withLock { finished } }
    var everRanOnTheMainThread: Bool { lock.withLock { ranOnMainThread } }

    func answer(_ palette: ArtworkPalette, for data: Data) { lock.withLock { answers[data] = palette } }
    func hold(_ data: Data) { lock.withLock { _ = held.insert(data) } }

    func release(_ data: Data) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released.insert(data)
            return waiting.removeValue(forKey: data)
        }
        continuation?.resume()
    }

    func extract(_ data: Data) async -> ArtworkPalette? {
        lock.withLock {
            calls.append(data)
            if Thread.isMainThread { ranOnMainThread = true }
        }
        if lock.withLock({ held.contains(data) && !released.contains(data) }) {
            await withCheckedContinuation { continuation in
                let proceed = lock.withLock { () -> Bool in
                    if released.contains(data) { return true }
                    waiting[data] = continuation
                    return false
                }
                if proceed { continuation.resume() }
            }
        }
        return lock.withLock {
            finished += 1
            return answers[data]
        }
    }
}

@Suite struct ArtworkTintCacheTests {
    func key(_ title: String, _ fingerprint: Int = 0) -> ArtworkTintKey {
        ArtworkTintKey(track: TrackIdentity(title: title), fingerprint: fingerprint)
    }

    let red = ArtworkPalette(primary: .fullRed, secondary: nil)
    let green = ArtworkPalette(primary: .fullGreen, secondary: nil)

    @Test func whatWasStoredIsFoundAndWhatWasNotIsNot() {
        var cache = ArtworkTintCache()
        #expect(cache.palette(for: key("a")) == nil)
        cache.store(red, for: key("a"))
        #expect(cache.palette(for: key("a")) == red)
        #expect(cache.palette(for: key("b")) == nil)
        #expect(cache.palette(for: key("a", 1)) == nil, "another cover is another entry")
    }

    @Test func theLeastRecentlyUsedEntryGoesFirst() {
        var cache = ArtworkTintCache(capacity: 2)
        cache.store(red, for: key("a"))
        cache.store(green, for: key("b"))
        cache.store(red, for: key("c"))
        #expect(cache.count == 2)
        #expect(cache.palette(for: key("a")) == nil)
        #expect(cache.palette(for: key("b")) == green)
        #expect(cache.palette(for: key("c")) == red)
    }

    @Test func lookingAnEntryUpKeepsItLonger() {
        var cache = ArtworkTintCache(capacity: 2)
        cache.store(red, for: key("a"))
        cache.store(green, for: key("b"))
        #expect(cache.palette(for: key("a")) == red)
        cache.store(red, for: key("c"))
        #expect(cache.palette(for: key("a")) == red)
        #expect(cache.palette(for: key("b")) == nil)
    }

    @Test func storingAnEntryAgainReplacesItWithoutGrowing() {
        var cache = ArtworkTintCache(capacity: 2)
        cache.store(red, for: key("a"))
        cache.store(green, for: key("a"))
        #expect(cache.count == 1)
        #expect(cache.palette(for: key("a")) == green)
    }

    @Test func aCacheAlwaysHoldsAtLeastOneEntry() {
        var cache = ArtworkTintCache(capacity: 0)
        cache.store(red, for: key("a"))
        #expect(cache.palette(for: key("a")) == red)
    }

    @Test func theKeyTellsCoversApartByTheirBytesAndTheirTrack() {
        let track = TrackIdentity(title: "a")
        let first = ArtworkTintKey(track: track, artwork: ArtworkData(data: Data([1, 2, 3]), mimeType: nil, revision: 1))
        let sameBytesLaterRevision = ArtworkTintKey(track: track, artwork: ArtworkData(data: Data([1, 2, 3]), mimeType: "image/png", revision: 9))
        let otherBytes = ArtworkTintKey(track: track, artwork: ArtworkData(data: Data([1, 2, 4]), mimeType: nil, revision: 1))
        let otherTrack = ArtworkTintKey(track: TrackIdentity(title: "b"), artwork: ArtworkData(data: Data([1, 2, 3]), mimeType: nil, revision: 1))
        #expect(first == sameBytesLaterRevision)
        #expect(first != otherBytes)
        #expect(first != otherTrack)
    }
}

/// What the tinter hands the player, and how often it works.
@Suite struct ArtworkTinterTests {
    final class Shown {
        var values: [ArtworkPalette?] = []
    }

    /// The tinters the test made. A tinter that nobody refers to any more is released, and an answer on its way has no one to
    /// go to, which is right for the app and would leave a test waiting for ever.
    final class Made {
        var tinters: [ArtworkTinter] = []
    }

    let extractor = FakeExtractor()
    let shown = Shown()
    let made = Made()
    let red = ArtworkPalette(primary: .fullRed, secondary: nil)
    let green = ArtworkPalette(primary: .fullGreen, secondary: .fullBlue)
    let coverA = Data([0xA1])
    let coverB = Data([0xB2])

    func makeTinter(capacity: Int = 32) -> ArtworkTinter {
        let extractor = extractor
        let shown = shown
        let tinter = ArtworkTinter(capacity: capacity, extract: { await extractor.extract($0) }, show: { shown.values.append($0) })
        made.tinters.append(tinter)
        return tinter
    }

    /// Lets what is already on its way to the main actor arrive, for a test that expects nothing to be shown.
    func letAnswersLand() async {
        for _ in 0..<100 { await Task.yield() }
    }

    func track(_ title: String) -> TrackIdentity { TrackIdentity(title: title) }
    func cover(_ data: Data, revision: Int = 1) -> ArtworkData { ArtworkData(data: data, mimeType: nil, revision: revision) }

    init() {
        extractor.answer(red, for: coverA)
        extractor.answer(green, for: coverB)
    }

    @Test func aTrackIsLookedAtOnceHoweverOftenTheStateChanges() async {
        let tinter = makeTinter()
        for _ in 0..<5 { tinter.update(track: track("a"), artwork: cover(coverA)) }
        #expect(await waitUntil { shown.values.count == 1 })
        for _ in 0..<5 { tinter.update(track: track("a"), artwork: cover(coverA)) }
        await letAnswersLand()
        #expect(extractor.callCount == 1)
        #expect(shown.values == [red])
    }

    @Test func theExtractionDoesNotBlockTheCallerAndAnswersLater() async {
        let tinter = makeTinter()
        extractor.hold(coverA)
        tinter.update(track: track("a"), artwork: cover(coverA))
        #expect(shown.values.isEmpty, "update returned before the colours were known")
        extractor.release(coverA)
        #expect(await waitUntil { shown.values.count == 1 })
        #expect(shown.values == [red])
        #expect(!extractor.everRanOnTheMainThread)
    }

    @Test func aTrackSeenBeforeComesFromTheCacheAtOnce() async {
        let tinter = makeTinter()
        tinter.update(track: track("a"), artwork: cover(coverA))
        #expect(await waitUntil { shown.values.count == 1 })
        tinter.update(track: track("b"), artwork: cover(coverB))
        #expect(await waitUntil { shown.values.count == 2 })
        tinter.update(track: track("a"), artwork: cover(coverA, revision: 3))
        #expect(shown.values == [red, green, red], "no waiting for the third")
        #expect(extractor.callCount == 2)
    }

    @Test func theSameBytesAreOneEntryWhateverTheRevision() async {
        let tinter = makeTinter()
        tinter.update(track: track("a"), artwork: cover(coverA, revision: 1))
        #expect(await waitUntil { shown.values.count == 1 })
        tinter.update(track: track("a"), artwork: cover(coverA, revision: 7))
        #expect(extractor.callCount == 1)
        #expect(shown.values == [red, red])
    }

    @Test func anotherCoverForTheSameTrackIsLookedAtAgain() async {
        let tinter = makeTinter()
        tinter.update(track: track("a"), artwork: cover(coverA))
        #expect(await waitUntil { shown.values.count == 1 })
        tinter.update(track: track("a"), artwork: cover(coverB, revision: 2))
        #expect(await waitUntil { shown.values.count == 2 })
        #expect(extractor.callCount == 2)
        #expect(shown.values == [red, green])
    }

    @Test func aTrackWithNoCoverClearsTheTint() async {
        let tinter = makeTinter()
        tinter.update(track: track("a"), artwork: cover(coverA))
        #expect(await waitUntil { shown.values.count == 1 })
        tinter.update(track: track("b"), artwork: nil)
        #expect(shown.values == [red, nil])
    }

    @Test func aCoverThatGivesNoColourGivesNoTint() async {
        let tinter = makeTinter()
        tinter.update(track: track("a"), artwork: cover(Data([0xFF])))
        #expect(await waitUntil { shown.values.count == 1 })
        #expect(shown.values == [nil])
    }

    @Test func aSlowAnswerForAnEarlierTrackNeverReplacesTheCurrentOne() async {
        let tinter = makeTinter()
        extractor.hold(coverA)
        tinter.update(track: track("a"), artwork: cover(coverA))
        tinter.update(track: track("b"), artwork: cover(coverB))
        #expect(await waitUntil { shown.values.count == 1 })
        extractor.release(coverA)
        #expect(await waitUntil { extractor.finishedCount == 2 })
        await letAnswersLand()
        #expect(shown.values == [green])
        // The slow answer was still worth keeping.
        tinter.update(track: track("a"), artwork: cover(coverA))
        #expect(shown.values == [green, red])
        #expect(extractor.callCount == 2)
    }

    @Test func stoppingDropsAnswersStillOnTheirWay() async {
        let tinter = makeTinter()
        extractor.hold(coverA)
        tinter.update(track: track("a"), artwork: cover(coverA))
        tinter.stop()
        extractor.release(coverA)
        #expect(await waitUntil { extractor.finishedCount == 1 })
        await letAnswersLand()
        #expect(shown.values.isEmpty)
    }

    @Test func afterStoppingTheSameTrackIsTintedAgain() async {
        let tinter = makeTinter()
        tinter.update(track: track("a"), artwork: cover(coverA))
        #expect(await waitUntil { shown.values.count == 1 })
        tinter.stop()
        tinter.update(track: track("a"), artwork: cover(coverA))
        #expect(shown.values == [red, red], "from the cache, at once")
    }

    @Test func theOldestTrackIsForgottenWhenTheCacheIsFull() async {
        let tinter = makeTinter(capacity: 1)
        tinter.update(track: track("a"), artwork: cover(coverA))
        #expect(await waitUntil { shown.values.count == 1 })
        tinter.update(track: track("b"), artwork: cover(coverB))
        #expect(await waitUntil { shown.values.count == 2 })
        tinter.update(track: track("a"), artwork: cover(coverA))
        #expect(await waitUntil { shown.values.count == 3 })
        #expect(extractor.callCount == 3)
    }

    @Test func theRealExtractionTintsFromARealImage() async {
        let shown = shown
        let tinter = ArtworkTinter(show: { shown.values.append($0) })
        made.tinters.append(tinter)
        let png = SyntheticImage.png(SyntheticImage.solid(.fullRed, size: 40))
        tinter.update(track: track("a"), artwork: cover(png))
        #expect(await waitUntil { shown.values.count == 1 })
        #expect(shown.values.first??.primary.isClose(to: .fullRed) == true)
    }
}
