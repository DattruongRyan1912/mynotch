import Foundation
import Testing
import YouTubeBridgeKit
@testable import MediaModule

@Suite struct YouTubeCaptionStoreTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var store = YouTubeCaptionStore()

    @Test mutating func captionsAreKeptPerVideoAsLyricLines() throws {
        store.apply(YouTubeTestMessages.captions("aaaaaaaaaaa"), at: now)
        store.apply(YouTubeTestMessages.captions("bbbbbbbbbbb", kind: .asr), at: now)
        let first = try #require(store.track(forVideo: "aaaaaaaaaaa"))
        #expect(first.lines == YouTubeTestMessages.lines)
        #expect(first.language == "vi")
        #expect(first.kind == .standard)
        #expect(try #require(store.track(forVideo: "bbbbbbbbbbb")).kind == .asr)
        #expect(store.track(forVideo: "ccccccccccc") == nil)
    }

    @Test mutating func theLatestCaptionsOfAVideoReplaceTheOldAndGetANewRevision() throws {
        store.apply(YouTubeTestMessages.captions(), at: now)
        let old = try #require(store.track(forVideo: YouTubeTestMessages.videoID))
        store.apply(YouTubeTestMessages.captions(YouTubeTestMessages.videoID, [CaptionEvent(time: 1, duration: 1, text: "delta")]), at: now)
        let new = try #require(store.track(forVideo: YouTubeTestMessages.videoID))
        #expect(new.lines.first?.text == "delta")
        #expect(new.revision != old.revision)
        #expect(store.tracks.count == 1)
    }

    @Test mutating func atMostThreeVideosAreKeptTheLeastRecentGoingFirst() {
        for id in ["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc"] { store.apply(YouTubeTestMessages.captions(id), at: now) }
        // Captions arriving again make a video the most recent.
        store.apply(YouTubeTestMessages.captions("aaaaaaaaaaa"), at: now)
        store.apply(YouTubeTestMessages.captions("ddddddddddd"), at: now)
        #expect(store.tracks.map(\.videoID) == ["ccccccccccc", "aaaaaaaaaaa", "ddddddddddd"])
        #expect(YouTubeCaptionStore.maxVideos == 3)
    }

    @Test mutating func clearDropsThatVideosCaptionsOnly() {
        store.apply(YouTubeTestMessages.captions("aaaaaaaaaaa"), at: now)
        store.apply(YouTubeTestMessages.captions("bbbbbbbbbbb"), at: now)
        store.apply(YouTubeTestMessages.playback("aaaaaaaaaaa"), at: now)
        store.apply(YouTubeTestMessages.clear("aaaaaaaaaaa"), at: now)
        #expect(store.tracks.map(\.videoID) == ["bbbbbbbbbbb"])
        #expect(store.playback?.message.videoID == "aaaaaaaaaaa")
        store.apply(YouTubeTestMessages.clear("zzzzzzzzzzz"), at: now)
        #expect(store.tracks.count == 1)
    }

    @Test mutating func theLatestPlaybackIsKeptWithItsArrivalTime() {
        #expect(store.playback == nil)
        store.apply(YouTubeTestMessages.playback(playing: true), at: now)
        store.apply(YouTubeTestMessages.playback("bbbbbbbbbbb", title: "Other", playing: false), at: now + 5)
        #expect(store.playback?.message.videoID == "bbbbbbbbbbb")
        #expect(store.playback?.message.isPlaying == false)
        #expect(store.playback?.arrivedAt == now + 5)
    }

    @Test mutating func everyMessageFromThePageCountsAsTheLastOneHeard() {
        #expect(store.lastPageMessageAt == nil)
        store.apply(YouTubeTestMessages.captions(), at: now)
        #expect(store.lastPageMessageAt == now)
        store.apply(YouTubeTestMessages.clear(), at: now + 3)
        #expect(store.lastPageMessageAt == now + 3)
        store.apply(YouTubeTestMessages.playback(), at: now + 4)
        #expect(store.lastPageMessageAt == now + 4)
        store.apply(YouTubeTestMessages.diag("content-cc on", from: .content), at: now + 5)
        #expect(store.lastPageMessageAt == now + 5)
        store.apply(YouTubeTestMessages.diag("page-seen xhr", from: .page), at: now + 6)
        #expect(store.lastPageMessageAt == now + 6)
    }

    @Test mutating func theServiceWorkersOwnDiagnosticsDoNotCount() {
        store.apply(YouTubeTestMessages.diag("sw-start v=0.1.2"), at: now)
        store.apply(YouTubeTestMessages.diag("sw-access youtube=withheld"), at: now)
        #expect(store.lastPageMessageAt == nil)
        store.apply(YouTubeTestMessages.playback(), at: now + 1)
        store.apply(YouTubeTestMessages.diag("sw-inject tabs=1 injected=1 failed=0"), at: now + 9)
        #expect(store.lastPageMessageAt == now + 1)
    }

    @Test mutating func removeAllForgetsEverything() {
        store.apply(YouTubeTestMessages.captions(), at: now)
        store.apply(YouTubeTestMessages.playback(), at: now)
        store.removeAll()
        #expect(store.tracks.isEmpty)
        #expect(store.playback == nil)
        #expect(store.lastPageMessageAt == nil)
    }
}
