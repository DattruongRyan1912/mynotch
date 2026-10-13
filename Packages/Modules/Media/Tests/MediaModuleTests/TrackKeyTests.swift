import Foundation
import Testing
@testable import MediaModule

@Suite struct TrackKeyTests {
    func key(
        artist: String? = "Artist", title: String? = "Song", album: String? = "Album", duration: Double = 200
    ) -> TrackKey? {
        TrackKey(artist: artist, title: title, album: album, duration: duration)
    }

    @Test func namesAreTrimmedAndWhitespaceCollapsed() throws {
        let tidy = try #require(key(artist: "  The   Artist\n", title: "\tSong \u{00A0} Name ", album: " Al  bum "))
        #expect(tidy.artist == "The Artist")
        #expect(tidy.title == "Song Name")
        #expect(tidy.album == "Al bum")
    }

    @Test func durationIsRoundedToWholeSeconds() throws {
        let up = try #require(key(duration: 199.6))
        let down = try #require(key(duration: 199.4))
        #expect(up.durationSeconds == 200)
        #expect(down.durationSeconds == 199)
        #expect(key(duration: 199.6) == key(duration: 200.2))
    }

    @Test func aMissingAlbumIsEmpty() throws {
        let noAlbum = try #require(key(album: nil))
        #expect(noAlbum.album == "")
    }

    @Test func withoutArtistTitleOrAUsableDurationThereIsNoKey() {
        #expect(key(artist: nil) == nil)
        #expect(key(artist: "  ") == nil)
        #expect(key(title: nil) == nil)
        #expect(key(title: "\n") == nil)
        for duration in [0, 0.4, -5, .nan, .infinity, 86_401] {
            #expect(key(duration: duration) == nil, "duration \(duration)")
        }
        #expect(key(duration: 0.5) != nil)
        #expect(key(duration: 86_400) != nil)
    }

    @Test func comesFromThePlayingState() throws {
        var state = NowPlayingState(title: "Song", artist: "Artist", album: "Album", durationSeconds: 200.4)
        #expect(TrackKey(state) == key())
        state.album = nil
        let withoutAlbum = try #require(TrackKey(state))
        #expect(withoutAlbum.album == "")
    }

    @Test func advertisementsAndTracksWithoutADurationHaveNoKey() {
        var state = NowPlayingState(title: "Song", artist: "Artist", album: "Album", durationSeconds: 200)
        state.isAdvertisement = true
        #expect(TrackKey(state) == nil)
        state.isAdvertisement = false
        state.durationSeconds = nil
        #expect(TrackKey(state) == nil)
        #expect(TrackKey(.empty) == nil)
    }

    @Test func cacheKeyIsAStableHashOfEveryField() throws {
        let base = try #require(key())
        let hash = base.cacheKey
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
        let same = try #require(key())
        #expect(hash == same.cacheKey)
        let variants = [
            key(artist: "Other"), key(title: "Other"), key(album: "Other"), key(album: nil), key(duration: 201),
        ]
        #expect(Set(variants.map { $0!.cacheKey }).union([hash]).count == variants.count + 1)
    }

    @Test func cacheKeyKeepsFieldsApart() throws {
        let one = try #require(key(artist: "ab", title: "c"))
        let other = try #require(key(artist: "a", title: "bc"))
        #expect(one.cacheKey != other.cacheKey)
    }
}
