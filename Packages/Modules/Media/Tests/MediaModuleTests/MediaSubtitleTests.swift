import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule

@Suite final class MediaSubtitleTests {
    let source = FakeNowPlayingSource()
    let client = FakeHTTPClient()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL
    let files = ScratchFolders.shared.reserveShort()

    static let film = "The Intern (2015) - Xem phim"
    static let srt = """
    1
    00:01:11,640 --> 00:01:14,530
    Freud said, "Love and work.

    2
    00:01:20,000 --> 00:01:21,000
    That's all there is.
    """
    static let lines = [
        LyricLine(time: 71.64, text: "Freud said, \"Love and work."), LyricLine(time: 74.53, text: ""),
        LyricLine(time: 80, text: "That's all there is."), LyricLine(time: 81, text: ""),
    ]

    init() {
        module = MediaModule(source: source, spectrum: FakeSpectrumSource(), lyricsClient: client, tokens: FakeTokenStore(), signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil })
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: storageBase)
        try? FileManager.default.removeItem(at: files)
    }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func playFilm(_ title: String = film, artist: String = "", duration: Double = 6_000) {
        source.emit(AdapterLines.track(title, artist: artist, bundle: "com.google.Chrome", elapsed: 60, duration: duration))
    }

    func file(_ text: String = srt, name: String = "intern.srt") throws -> URL {
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let url = files.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func aLoadedFileShowsItsLinesForTheFilmEvenWithLyricsAndCaptionsOff() async throws {
        await harness.registry.bootstrap()
        playFilm()
        await settle { store.state.isActive }
        #expect(!store.lyricsAreOn)
        #expect(module.loadSubtitles(from: try file()))
        #expect(store.syncedLyrics == Self.lines)
        #expect(store.lyricsAreOn)
        #expect(module.subtitles.current?.name == "intern.srt")
    }

    @Test func theSubtitlesWinOverLyricsFromTheWeb() async throws {
        harness.settings.set(true, for: keys.lyrics)
        await harness.registry.bootstrap()
        // A short clip with an artist, which lrclib would be asked about without the subtitles.
        playFilm(artist: "Channel", duration: 200)
        await settle { store.state.isActive }
        module.loadSubtitles(from: try file())
        harness.scheduler.advance(by: MediaModule.browserLyricsDelay)
        await settle { !client.requests.isEmpty }
        #expect(client.requests.isEmpty)
        #expect(store.syncedLyrics == Self.lines)
    }

    @Test func shiftingMovesTheLinesAndResettingPutsThemBack() async throws {
        await harness.registry.bootstrap()
        playFilm()
        await settle { store.state.isActive }
        module.loadSubtitles(from: try file())
        module.shiftSubtitles(by: -SubtitleBook.smallStep)
        #expect(store.syncedLyrics?.first?.time == 71.14)
        module.resetSubtitleDelay()
        #expect(store.syncedLyrics == Self.lines)
    }

    @Test func theSubtitlesAreForTheirFilmAndComeBackWithIt() async throws {
        await harness.registry.bootstrap()
        playFilm()
        await settle { store.state.isActive }
        module.loadSubtitles(from: try file())
        playFilm("Another film")
        await settle { store.state.title == "Another film" }
        #expect(store.syncedLyrics == nil)
        #expect(!store.lyricsAreOn)
        #expect(module.subtitles.current == nil)
        playFilm()
        await settle { store.state.title == Self.film }
        #expect(store.syncedLyrics == Self.lines)
    }

    @Test func removingClearsTheRow() async throws {
        await harness.registry.bootstrap()
        playFilm()
        await settle { store.state.isActive }
        module.loadSubtitles(from: try file())
        module.removeSubtitles()
        #expect(store.syncedLyrics == nil)
        #expect(!store.lyricsAreOn)
    }

    @Test func aFileWithNoSubtitleIsRefusedAndNamed() async throws {
        await harness.registry.bootstrap()
        playFilm()
        await settle { store.state.isActive }
        #expect(!module.loadSubtitles(from: try file("not a subtitle", name: "notes.txt")))
        #expect(module.subtitles.unreadableName == "notes.txt")
        #expect(store.syncedLyrics == nil)
    }

    @Test func nothingIsLoadedWhileNothingPlays() async throws {
        await harness.registry.bootstrap()
        #expect(!module.loadSubtitles(from: try file()))
    }
}
