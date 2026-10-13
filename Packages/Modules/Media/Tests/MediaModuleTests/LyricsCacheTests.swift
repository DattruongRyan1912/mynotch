import Foundation
import Testing
@testable import MediaModule

@Suite final class LyricsCacheTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "LyricsCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let track = TrackKey(artist: "Artist", title: "Song", album: "Album", duration: 200)!

    deinit { try? FileManager.default.removeItem(at: root) }

    var cache: LyricsCache { LyricsCache(directory: root.appending(path: "Modules/media/lyrics", directoryHint: .isDirectory)) }

    @Test func nothingIsCreatedUntilSomethingIsStored() {
        #expect(cache.load(track) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path()))
    }

    @Test(arguments: [
        LyricsResult.synced([LyricLine(time: 1.5, text: "Xin chào"), LyricLine(time: 4, text: "")]),
        .plain("Lời\nbài hát"),
        .instrumental,
        .notFound,
    ])
    func everyAnswerComesBackAsItWentIn(result: LyricsResult) {
        cache.store(result, for: track)
        #expect(cache.load(track) == result)
    }

    @Test func unavailableIsNeverKept() {
        cache.store(.unavailable("Rate limited (HTTP 429)"), for: track)
        #expect(cache.load(track) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path()))
    }

    @Test func aFileThatIsNotAnAnswerIsNotACacheHit() throws {
        let directory = cache.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(track.cacheKey).json")
        for content in ["", "{", "[]", #"{"unavailable":{"_0":"x"}}"#] {
            try Data(content.utf8).write(to: file)
            #expect(cache.load(track) == nil, "content: \(content)")
        }
    }

    @Test func tracksDoNotShareEntries() {
        cache.store(.notFound, for: track)
        #expect(cache.load(TrackKey(artist: "Artist", title: "Song", album: "Album", duration: 260)!) == nil)
    }

    @Test func storingAgainReplacesTheEntry() {
        cache.store(.notFound, for: track)
        cache.store(.instrumental, for: track)
        #expect(cache.load(track) == .instrumental)
    }

    @Test func entriesHoldNoTrackNames() throws {
        cache.store(.synced([LyricLine(time: 1, text: "la")]), for: track)
        let text = try String(contentsOf: cache.directory.appending(path: "\(track.cacheKey).json"), encoding: .utf8)
        #expect(!text.contains("Artist") && !text.contains("Song") && !text.contains("Album"))
    }
}
