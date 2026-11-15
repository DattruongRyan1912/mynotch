import AppKit
import Foundation
import Testing
@testable import MediaModule

@Suite struct AppPlayerControlTests {
    static let musicList = PlayerScriptValue.list([
        .text("playing"), .text("Song"), .text("Artist"), .text("Album"), .number(12.5), .number(213), .text("98765"),
    ])
    static let spotifyList = PlayerScriptValue.list([
        .text("paused"), .text("Track"), .text("Singer"), .text("Record"), .number(30), .number(180_000), .text("spotify:track:abc"),
        .text("https://i.scdn.co/image/abc"),
    ])

    func control(_ player: KnownPlayer, _ answers: [PlayerScriptResult], fetch: @escaping (URL) async -> Data? = { _ in nil }) -> (AppleScriptPlayerControl, FakePlayerScriptRunner) {
        let runner = FakePlayerScriptRunner(answers)
        return (AppleScriptPlayerControl(player: player, runner: runner, fetchArtwork: fetch), runner)
    }

    // MARK: the scripts never start an app

    @Test(arguments: KnownPlayer.allCases) func everyScriptChecksThatTheAppRunsBeforeItTellsItAnything(player: KnownPlayer) {
        var scripts = [PlayerScripts.poll(player)]
        if let artwork = PlayerScripts.artwork(player) { scripts.append(artwork) }
        for command in [AppPlayerCommand.play, .pause, .togglePlayPause, .next, .previous, .seek(seconds: 12.5)] {
            scripts.append(PlayerScripts.command(command, for: player))
        }
        for script in scripts {
            let check = "if application id \"\(player.bundleID)\" is running then"
            #expect(script.hasPrefix(check), "\(script)")
            // The `tell` is inside the check, so that an app that is not running is never started by it.
            #expect(script.components(separatedBy: "tell application").count == 2, "\(script)")
            let tell = script.range(of: "tell application id")!
            #expect(tell.lowerBound > script.range(of: check)!.upperBound)
            // A hung app costs two seconds, not the system's two minutes behind which every later read and command would wait.
            let timeout = script.range(of: "with timeout of 2 seconds")!
            #expect(timeout.lowerBound > script.range(of: check)!.upperBound && timeout.upperBound < tell.lowerBound, "\(script)")
            #expect(script.range(of: "end timeout")!.lowerBound > script.range(of: "end tell")!.upperBound, "\(script)")
            #expect(script.hasSuffix("end if\nreturn {\"notrunning\"}"), "\(script)")
            for forbidden in ["launch", "activate", "run script", "open ", "reopen", "do shell", "quit", "System Events", "make new"] {
                #expect(!script.contains(forbidden), "\(forbidden) in \(script)")
            }
            // By bundle id, so that no app's name is looked up on this Mac (and none asked for).
            #expect(!script.contains("tell application \""))
        }
    }

    @Test func theCommandsAreTheAppsOwnWords() {
        #expect(PlayerScripts.command(.play, for: .music).contains("\n            play\n"))
        #expect(PlayerScripts.command(.pause, for: .spotify).contains("\n            pause\n"))
        #expect(PlayerScripts.command(.togglePlayPause, for: .music).contains("\n            playpause\n"))
        #expect(PlayerScripts.command(.next, for: .spotify).contains("\n            next track\n"))
        #expect(PlayerScripts.command(.previous, for: .music).contains("\n            previous track\n"))
        #expect(PlayerScripts.command(.seek(seconds: 61.2349), for: .music).contains("\n            set player position to 61.235\n"))
    }

    @Test func aSeekIsAPlainNumberWithAPointHeldInRange() {
        #expect(PlayerScripts.command(.seek(seconds: -5), for: .music).contains("set player position to 0.000"))
        #expect(PlayerScripts.command(.seek(seconds: 1e300), for: .music).contains("set player position to 10000000.000"))
        #expect(PlayerScripts.command(.seek(seconds: 0.5), for: .spotify).contains("set player position to 0.500"))
    }

    @Test func musicsCoverIsReadAsDataAndSpotifyHasNoSuchScript() {
        #expect(PlayerScripts.artwork(.music)?.contains("data of artwork 1 of t") == true)
        #expect(PlayerScripts.artwork(.spotify) == nil)
        #expect(PlayerScripts.poll(.spotify).contains("artwork url of t"))
        #expect(!PlayerScripts.poll(.music).contains("artwork"))
    }

    // MARK: reading

    @Test func musicsReadIsATrackWithItsLengthInSeconds() async {
        let (control, _) = control(.music, [.value(Self.musicList), .value(.missing)])
        let reading = await control.read()
        #expect(reading == .snapshot(AppPlayerSnapshot(
            isPlaying: true, title: "Song", artist: "Artist", album: "Album", durationSeconds: 213, positionSeconds: 12.5, trackID: "98765"
        )))
    }

    @Test func spotifysLengthIsInMillisecondsAndItGivesAnAddressForTheCover() async {
        let (control, _) = control(.spotify, [.value(Self.spotifyList)])
        guard case .snapshot(let snapshot) = await control.read() else { Issue.record("not a snapshot"); return }
        #expect(snapshot.isPlaying == false)
        #expect(snapshot.durationSeconds == 180)
        #expect(snapshot.positionSeconds == 30)
        #expect(snapshot.trackID == "spotify:track:abc")
        #expect(snapshot.artworkURL == URL(string: "https://i.scdn.co/image/abc"))
    }

    @Test func aNumberThatCameAsTextWithACommaIsRead() async {
        let (control, _) = control(.music, [.value(.list([
            .text("playing"), .text("Song"), .text(""), .text(""), .text("12,5"), .text("200,25"), .number(5),
        ])), .value(.missing)])
        guard case .snapshot(let snapshot) = await control.read() else { Issue.record("not a snapshot"); return }
        #expect(snapshot.positionSeconds == 12.5)
        #expect(snapshot.durationSeconds == 200.25)
        #expect(snapshot.artist == nil && snapshot.album == nil, "empty text is no artist")
        #expect(snapshot.trackID == "5")
    }

    @Test func theAnswersThatAreNotATrackAreTheirOwnReadings() async {
        let cases: [(PlayerScriptResult, AppPlayerReading)] = [
            (.value(.list([.text("stopped")])), .stopped),
            (.value(.list([.text("notrunning")])), .notRunning),
            (.notRunning, .notRunning),
            (.notAllowed, .notAllowed),
            (.failed, .failed),
            (.value(.missing), .failed),
            (.value(.text("playing")), .failed),
            (.value(.list([.text("playing"), .text("Song")])), .failed),
            (.value(.list([.text("bogus"), .text("Song"), .text(""), .text(""), .number(1), .number(2), .text("3")])), .failed),
            (.value(.list([.text("playing"), .text(""), .text(""), .text(""), .number(1), .number(2), .text("3")])), .failed),
        ]
        for (answer, expected) in cases {
            let (control, _) = control(.music, [answer])
            #expect(await control.read() == expected, "\(answer)")
        }
    }

    @Test func aPlayingAndAnEmptyOrNonsenseLengthAndPositionAreHandled() async {
        let (control, _) = control(.music, [.value(.list([
            .text("fast forwarding"), .text("Song"), .text("A"), .text("B"), .number(-1), .number(0), .text("1"),
        ])), .value(.missing)])
        guard case .snapshot(let snapshot) = await control.read() else { Issue.record("not a snapshot"); return }
        #expect(snapshot.isPlaying)
        #expect(snapshot.positionSeconds == nil)
        #expect(snapshot.durationSeconds == nil)
    }

    // MARK: the cover, once per track

    @Test func musicsCoverIsReadOnceForATrackNotAtTheRateOfThePoll() async {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let (control, runner) = control(.music, [.value(Self.musicList), .value(.data(bytes)), .value(Self.musicList), .value(Self.musicList)])
        guard case .snapshot(let first) = await control.read() else { Issue.record("not a snapshot"); return }
        #expect(first.artwork == bytes)
        #expect(runner.scripts.count == 2, "the poll, then the cover")
        for _ in 0..<3 {
            guard case .snapshot(let again) = await control.read() else { Issue.record("not a snapshot"); return }
            #expect(again.artwork == bytes)
        }
        #expect(runner.scripts.count == 5, "three more polls and no more reads of the cover")
        #expect(runner.scripts.filter { $0.contains("artwork 1") }.count == 1)
    }

    @Test func aTrackWithNoCoverIsNotAskedAgainForEitherAndANewTrackIsAskedAgain() async {
        let other = PlayerScriptValue.list([.text("playing"), .text("Other"), .text("A"), .text("B"), .number(1), .number(100), .text("55")])
        let (control, runner) = control(.music, [.value(Self.musicList), .value(.missing), .value(Self.musicList), .value(other), .value(.data(Data([7])))])
        guard case .snapshot(let first) = await control.read() else { Issue.record("not a snapshot"); return }
        #expect(first.artwork == nil)
        _ = await control.read()
        #expect(runner.scripts.filter { $0.contains("artwork 1") }.count == 1)
        guard case .snapshot(let next) = await control.read() else { Issue.record("not a snapshot"); return }
        #expect(next.artwork == Data([7]))
        #expect(runner.scripts.filter { $0.contains("artwork 1") }.count == 2)
    }

    @Test func spotifysCoverIsFetchedOncePerTrackFromTheAddressItGaveAndNotWaitedFor() async {
        let fetched = FetchLog()
        let (control, _) = control(.spotify, [.value(Self.spotifyList)], fetch: { url in
            await fetched.record(url)
            return Data([1, 2])
        })
        guard case .snapshot(let first) = await control.read() else { Issue.record("not a snapshot"); return }
        #expect(first.artwork == nil, "the read does not wait for the cover")
        for _ in 0..<200 where await fetched.urls.isEmpty { await Task.yield() }
        for _ in 0..<3 {
            for _ in 0..<50 { await Task.yield() }
            guard case .snapshot(let snapshot) = await control.read() else { Issue.record("not a snapshot"); return }
            #expect(snapshot.artwork == Data([1, 2]), "the next read has it")
        }
        #expect(await fetched.urls == [URL(string: "https://i.scdn.co/image/abc")!])
    }

    @Test func aSlowServiceNeverHoldsTheReadOfSpotifysStateAndPosition() async {
        let gate = Release()
        let (control, runner) = control(.spotify, [.value(Self.spotifyList)], fetch: { _ in
            await gate.wait()
            return Data([9])
        })
        for _ in 0..<5 {
            guard case .snapshot(let snapshot) = await control.read() else { Issue.record("not a snapshot"); return }
            #expect(snapshot.title == "Track")
            #expect(snapshot.artwork == nil)
        }
        #expect(runner.scripts.count == 5, "five reads, though the cover has not come")
        await gate.open()
    }

    @Test func aCoverTheServiceDoesNotGiveLeavesTheTrackWithoutOne() async {
        let (control, _) = control(.spotify, [.value(Self.spotifyList)])
        guard case .snapshot(let snapshot) = await control.read() else { Issue.record("not a snapshot"); return }
        #expect(snapshot.artwork == nil)
        for _ in 0..<50 { await Task.yield() }
        guard case .snapshot(let again) = await control.read() else { Issue.record("not a snapshot"); return }
        #expect(again.artwork == nil)
    }

    @Test func onlySpotifysOwnImageServiceOverHTTPSIsFetched() {
        for url in ["https://i.scdn.co/image/abc", "https://scdn.co/x", "https://mosaic.scdn.co/640/abc", "https://I.SCDN.CO/image/abc"] {
            #expect(SpotifyArtwork.isAllowed(URL(string: url)!), "\(url)")
        }
        for url in [
            "http://i.scdn.co/image/abc", "https://evil.example/image", "https://scdn.co.evil.example/x", "https://notscdn.co/x",
            "https://i.scdn.co.evil.example/image", "file:///etc/passwd", "ftp://i.scdn.co/x", "https://localhost/x", "https://192.168.0.1/x",
        ] {
            #expect(!SpotifyArtwork.isAllowed(URL(string: url)!), "\(url)")
        }
    }

    // MARK: commands

    @Test func aCommandSaysWhatCameOfIt() async {
        let cases: [(PlayerScriptResult, AppPlayerOutcome)] = [
            (.value(.number(1)), .done), (.value(.missing), .done), (.value(.list([.text("notrunning")])), .notRunning),
            (.notRunning, .notRunning), (.notAllowed, .notAllowed), (.failed, .failed),
        ]
        for (answer, outcome) in cases {
            let (control, runner) = control(.spotify, [answer])
            #expect(await control.perform(.togglePlayPause) == outcome, "\(answer)")
            #expect(runner.scripts == [PlayerScripts.command(.togglePlayPause, for: .spotify)])
        }
    }

    // MARK: the real runner (with a script that touches no app)

    @Test func theRealRunnerTurnsADescriptorIntoPlainValues() async {
        let result = await SystemPlayerScriptRunner().run("return {\"text\", 12, 2.5, true, missing value, {\"inner\"}}")
        guard case .value(.list(let items)) = result else { Issue.record("not a list: \(result)"); return }
        #expect(items.count == 6)
        #expect(items[0] == .text("text"))
        #expect(items[1] == .number(12))
        #expect(items[2] == .number(2.5))
        #expect(items[4] == .missing)
        #expect(items[5] == .list([.text("inner")]))
    }

    @Test func aScriptThatFailsIsFailedAndOneThatDoesNotCompileIsToo() async {
        #expect(await SystemPlayerScriptRunner().run("error number 1234") == .failed)
        #expect(await SystemPlayerScriptRunner().run("this is not (( a script") == .failed)
    }

    @Test func theErrorNumbersOfAppleEvents() {
        #expect(SystemPlayerScriptRunner.result(forErrorNumber: -1743) == .notAllowed)
        #expect(SystemPlayerScriptRunner.result(forErrorNumber: -600) == .notRunning)
        #expect(SystemPlayerScriptRunner.result(forErrorNumber: -609) == .notRunning)
        #expect(SystemPlayerScriptRunner.result(forErrorNumber: -1728) == .failed)
        #expect(SystemPlayerScriptRunner.result(forErrorNumber: nil) == .failed)
    }

    @Test func theInertRunnerAnswersNothingAndSendsNothing() async {
        #expect(await InertScriptRunner().run("anything") == .failed)
    }
}

private actor FetchLog {
    private(set) var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }
}
