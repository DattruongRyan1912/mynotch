import CryptoKit
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

@Suite struct TrackKeyLookupTests {
    func state(
        bundle: String? = "com.google.Chrome", parent: String? = nil, title: String, artist: String, album: String? = nil,
        duration: Double = 200
    ) -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: bundle, parentApplicationBundleIdentifier: parent, title: title, artist: artist, album: album,
            durationSeconds: duration
        )
    }

    @Test(arguments: [
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac",
        "org.mozilla.firefox", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.google.Chrome.helper",
    ])
    func browsersGetTheirTitlesCleaned(bundle: String) throws {
        let key = try #require(TrackKey(state(bundle: bundle, title: "Song (Official Video)", artist: "ArtistVEVO")))
        #expect(key.lookupArtist == "Artist")
        #expect(key.lookupTitle == "Song")
    }

    @Test func aHelperProcessCountsThroughItsParent() throws {
        let key = try #require(TrackKey(state(bundle: "com.example.helper", parent: "org.mozilla.firefox", title: "Song (Lyrics)", artist: "Chan")))
        #expect(key.lookupTitle == "Song")
    }

    @Test func anAlbumlessDashedTitleIsCleanedWhateverThePlayer() throws {
        let key = try #require(TrackKey(state(bundle: "com.example.Player", title: "Queen - Radio Ga Ga (Official Video)", artist: "Channel")))
        #expect(key.lookupArtist == "Queen")
        #expect(key.lookupTitle == "Radio Ga Ga")
    }

    @Test func otherPlayersWithAnAlbumAreLookedUpAsReported() throws {
        let key = try #require(TrackKey(state(bundle: "com.spotify.client", title: "Song - Remastered (Live)", artist: "Artist", album: "Album")))
        #expect(key.lookupArtist == "Artist")
        #expect(key.lookupTitle == "Song - Remastered (Live)")
    }

    @Test func aBrowserTrackWithAnAlbumKeepsItsMetadataAndOnlyLosesTheNoise() throws {
        let tagged = try #require(TrackKey(state(title: "Bohemian Rhapsody - Remastered 2011", artist: "Queen", album: "A Night at the Opera")))
        #expect(tagged.lookupArtist == "Queen")
        #expect(tagged.lookupTitle == "Bohemian Rhapsody - Remastered 2011")
        let noisy = try #require(TrackKey(state(title: "Hello - Radio Edit (Official Video)", artist: "AdeleVEVO", album: "25")))
        #expect(noisy.lookupArtist == "AdeleVEVO")
        #expect(noisy.lookupTitle == "Hello - Radio Edit")
    }

    @Test func aPipeSeparatedVideoTitleIsAskedBySongAndArtist() throws {
        let key = try #require(TrackKey(state(
            title: "CHẠY NGAY ĐI | RUN NOW | SƠN TÙNG M-TP | Official Music Video", artist: "Sơn Tùng M-TP Official", duration: 273.5
        )))
        #expect(key.lookupArtist == "Sơn Tùng M-TP")
        #expect(key.lookupTitle == "CHẠY NGAY ĐI")
        // The cache still goes by what the player reported.
        #expect(key.title == "CHẠY NGAY ĐI | RUN NOW | SƠN TÙNG M-TP | Official Music Video")
        #expect(key.artist == "Sơn Tùng M-TP Official")
        #expect(key.durationSeconds == 274)
    }

    @Test func aPipeTitleWithAnAlbumIsNotSplit() throws {
        // The album means the player tagged the track itself: a pipe belongs to the title, as a dash does.
        let key = try #require(TrackKey(state(title: "Chạy Ngay Đi | Run Now", artist: "Sơn Tùng M-TP", album: "Single")))
        #expect(key.lookupArtist == "Sơn Tùng M-TP")
        #expect(key.lookupTitle == "Chạy Ngay Đi | Run Now")
    }

    @Test func theKeyKeepsTheOriginalFields() throws {
        let key = try #require(TrackKey(state(title: "Queen - Radio Ga Ga (Official Video)", artist: "QueenVEVO")))
        #expect(key.artist == "QueenVEVO")
        #expect(key.title == "Queen - Radio Ga Ga (Official Video)")
    }

    @Test func theCacheKeyIsVersioned() throws {
        let key = try #require(TrackKey(artist: "Artist", title: "Song", album: "Album", duration: 200))
        let unversioned = ["Artist", "Song", "Album", "200"].joined(separator: "\u{1F}")
        let withVersion = [unversioned, "v7"].joined(separator: "\u{1F}")
        #expect(key.cacheKey == hash(withVersion))
        // Entries written before the version existed are never found again.
        #expect(key.cacheKey != hash(unversioned))
    }

    @Test func namesAreNormalisedToTheComposedForm() throws {
        let composed = "Nhạc Việt – Đừng Hỏi Em".precomposedStringWithCanonicalMapping
        let decomposed = composed.decomposedStringWithCanonicalMapping
        #expect(decomposed.unicodeScalars.count > composed.unicodeScalars.count)
        let nfc = try #require(TrackKey(artist: composed, title: composed, album: composed, duration: 200))
        let nfd = try #require(TrackKey(artist: decomposed, title: decomposed, album: decomposed, duration: 200))
        // Swift compares the two as equal anyway; what lrclib is sent, and the cache file name, must be the same too.
        #expect(nfd.title.unicodeScalars.count == composed.unicodeScalars.count)
        #expect(nfd.artist.unicodeScalars.count == composed.unicodeScalars.count)
        #expect(nfd.album.unicodeScalars.count == composed.unicodeScalars.count)
        #expect(nfd.cacheKey == nfc.cacheKey)
    }

    func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@Suite struct TrackKeyAppleTests {
    func state(bundle: String? = "com.apple.Music", id: String? = "1856960468") -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: bundle, title: "Song", artist: "Artist", album: "Album", durationSeconds: 200, uniqueIdentifier: id
        )
    }

    @Test func aMusicTrackWithACatalogIdCarriesIt() throws {
        #expect(try #require(TrackKey(state())).appleCatalogID == "1856960468")
    }

    @Test func nothingElseCarriesOne() throws {
        for bundle in ["com.spotify.client", "com.google.Chrome", "com.apple.Music.helper", "com.apple.music", nil] {
            #expect(try #require(TrackKey(state(bundle: bundle))).appleCatalogID == nil, "\(bundle ?? "nil")")
        }
        for id in [nil, "", "ABC", "1219::1227", "-5"] {
            #expect(try #require(TrackKey(state(id: id))).appleCatalogID == nil, "\(id ?? "nil")")
        }
        #expect(TrackKey(artist: "Artist", title: "Song", album: "Album", duration: 200)?.appleCatalogID == nil)
    }

    @Test func theKeyEncodesWhetherAppleIsAsked() throws {
        let asked = try #require(TrackKey(state()))
        var notAsked = asked
        notAsked.appleCatalogID = nil
        let fields = ["Artist", "Song", "Album", "200"]
        func hash(_ version: String) -> String {
            SHA256.hash(data: Data((fields + [version]).joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
        }
        #expect(TrackKey.cacheVersion == "v7")
        #expect(notAsked.cacheKey == hash("v7"))
        #expect(asked.cacheKey == hash("v7+am"))
        #expect(asked.cacheKey != notAsked.cacheKey)
    }

    @Test func theCatalogIdItselfIsNotPartOfTheKey() throws {
        let one = try #require(TrackKey(state(id: "1")))
        let other = try #require(TrackKey(state(id: "2")))
        #expect(one.cacheKey == other.cacheKey)
    }
}
