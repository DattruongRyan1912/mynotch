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

    @Test mutating func everyMessageCountsAsTheLastOneHeard() {
        #expect(store.lastMessageAt == nil)
        store.apply(YouTubeTestMessages.captions(), at: now)
        #expect(store.lastMessageAt == now)
        store.apply(YouTubeTestMessages.clear(), at: now + 3)
        #expect(store.lastMessageAt == now + 3)
    }

    @Test mutating func removeAllForgetsEverything() {
        store.apply(YouTubeTestMessages.captions(), at: now)
        store.apply(YouTubeTestMessages.playback(), at: now)
        store.removeAll()
        #expect(store.tracks.isEmpty)
        #expect(store.playback == nil)
        #expect(store.lastMessageAt == nil)
    }
}
