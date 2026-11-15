import Foundation
import Testing
@testable import MediaModule

@Suite struct AppPlayerSnapshotTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func nextRevision() -> () -> Int {
        var revision = 0
        return {
            revision += 1
            return revision
        }
    }

    // MARK: the notifications of the players

    @Test func musicSaysItsTrackInMilliseconds() {
        let info: [AnyHashable: Any] = [
            "Player State": "Playing", "Name": "Song", "Artist": "Artist", "Album": "Album", "Total Time": 213_500, "Persistent ID": "ABCDEF0123456789",
        ]
        #expect(KnownPlayer.music.event(fromNotification: info) == .track(AppPlayerSnapshot(
            isPlaying: true, title: "Song", artist: "Artist", album: "Album", durationSeconds: 213.5, trackID: "ABCDEF0123456789"
        )))
    }

    @Test func spotifySaysItsPositionToo() {
        let info: [AnyHashable: Any] = [
            "Player State": "Paused", "Name": "Track", "Artist": "Singer", "Album": "Record", "Duration": 180_000, "Playback Position": 42.25,
            "Track ID": "spotify:track:abc",
        ]
        #expect(KnownPlayer.spotify.event(fromNotification: info) == .track(AppPlayerSnapshot(
            isPlaying: false, title: "Track", artist: "Singer", album: "Record", durationSeconds: 180, positionSeconds: 42.25, trackID: "spotify:track:abc"
        )))
    }

    @Test func theStateIsReadWhateverItsCase() {
        for state in ["Playing", "playing", "PLAYING"] {
            guard case .track(let snapshot)? = KnownPlayer.music.event(fromNotification: ["Player State": state, "Name": "S"]) else {
                Issue.record("not a track: \(state)")
                continue
            }
            #expect(snapshot.isPlaying)
        }
        guard case .track(let paused)? = KnownPlayer.music.event(fromNotification: ["Player State": "paused", "Name": "S"]) else { Issue.record("not a track"); return }
        #expect(!paused.isPlaying)
    }

    @Test func stoppedAndAnythingWithoutATitleMeansNothingIsLoaded() {
        #expect(KnownPlayer.music.event(fromNotification: ["Player State": "Stopped"]) == .stopped)
        #expect(KnownPlayer.music.event(fromNotification: ["Player State": "Stopped", "Name": "Song"]) == .stopped)
        #expect(KnownPlayer.music.event(fromNotification: ["Player State": "Playing"]) == .stopped)
        #expect(KnownPlayer.music.event(fromNotification: ["Player State": "Playing", "Name": "   "]) == .stopped)
        #expect(KnownPlayer.spotify.event(fromNotification: ["Player State": "Something else", "Name": "Song"]) == .stopped)
    }

    @Test func aPayloadWithNoStateIsNotOneOfTheirs() {
        #expect(KnownPlayer.music.event(fromNotification: [:]) == nil)
        #expect(KnownPlayer.music.event(fromNotification: ["Name": "Song"]) == nil)
        #expect(KnownPlayer.music.event(fromNotification: ["Player State": 3, "Name": "Song"]) == nil)
    }

    @Test func idsAndNumbersAreTakenInWhateverTypeTheAppUsed() {
        let info: [AnyHashable: Any] = ["Player State": "Playing", "Name": "Song", "Total Time": "120000", "Persistent ID": 1234567890123 as NSNumber]
        guard case .track(let snapshot)? = KnownPlayer.music.event(fromNotification: info) else { Issue.record("not a track"); return }
        #expect(snapshot.durationSeconds == 120)
        #expect(snapshot.trackID == "1234567890123")
    }

    @Test func aLengthOfNothingOrLessIsNoLengthAndNegativePositionsAreDropped() {
        let info: [AnyHashable: Any] = ["Player State": "Playing", "Name": "Song", "Duration": 0, "Playback Position": -3.0]
        guard case .track(let snapshot)? = KnownPlayer.spotify.event(fromNotification: info) else { Issue.record("not a track"); return }
        #expect(snapshot.durationSeconds == nil)
        #expect(snapshot.positionSeconds == nil)
    }

    @Test func musicsNotificationHasNoPositionEvenIfOneIsPutInIt() {
        let info: [AnyHashable: Any] = ["Player State": "Playing", "Name": "Song", "Playback Position": 9.0]
        guard case .track(let snapshot)? = KnownPlayer.music.event(fromNotification: info) else { Issue.record("not a track"); return }
        #expect(snapshot.positionSeconds == nil)
    }

    @Test func theKnownPlayersHaveTheirOwnBundleIDsNamesAndNotifications() {
        #expect(KnownPlayer.music.bundleID == "com.apple.Music")
        #expect(KnownPlayer.spotify.bundleID == "com.spotify.client")
        #expect(KnownPlayer.music.notificationName == "com.apple.Music.playerInfo")
        #expect(KnownPlayer.spotify.notificationName == "com.spotify.client.PlaybackStateChanged")
        #expect(KnownPlayer.music.name == "Music")
        #expect(KnownPlayer.spotify.name == "Spotify")
        #expect(KnownPlayer.player(forBundleID: "com.spotify.client") == .spotify)
        #expect(KnownPlayer.player(forBundleID: "org.videolan.vlc") == nil)
    }

    // MARK: a session

    @Test func aSessionFromANotificationWithAPositionAnchorsIt() {
        let snapshot = AppPlayerSnapshot(isPlaying: true, title: "T", positionSeconds: 30)
        let session = AppPlayerSession(notified: snapshot, replacing: nil, at: now, revision: nextRevision())
        #expect(session.anchor == PlaybackAnchor(elapsedSeconds: 30, timestamp: now, rate: 1))
        let paused = AppPlayerSession(notified: AppPlayerSnapshot(isPlaying: false, title: "T", positionSeconds: 30), replacing: nil, at: now, revision: nextRevision())
        #expect(paused.anchor?.rate == 0)
    }

    @Test func withoutAPositionTheEarlierSessionOfTheSameTrackMovesOnAndStopsWhereItWasWhenPaused() {
        let revision = nextRevision()
        let first = AppPlayerSession(read: AppPlayerSnapshot(isPlaying: true, title: "T", positionSeconds: 10, trackID: "1"), replacing: nil, at: now, revision: revision)
        let paused = AppPlayerSession(
            notified: AppPlayerSnapshot(isPlaying: false, title: "T", trackID: "1"), replacing: first, at: now.addingTimeInterval(5), revision: revision
        )
        #expect(paused.anchor == PlaybackAnchor(elapsedSeconds: 15, timestamp: now.addingTimeInterval(5), rate: 0), "it played five seconds")
        let resumed = AppPlayerSession(
            notified: AppPlayerSnapshot(isPlaying: true, title: "T", trackID: "1"), replacing: paused, at: now.addingTimeInterval(60), revision: revision
        )
        #expect(resumed.anchor == PlaybackAnchor(elapsedSeconds: 15, timestamp: now.addingTimeInterval(60), rate: 1), "a pause does not move it")
    }

    @Test func aNewTrackHasNoPositionUntilSomethingSays() {
        let revision = nextRevision()
        let first = AppPlayerSession(read: AppPlayerSnapshot(isPlaying: true, title: "T", positionSeconds: 10, trackID: "1"), replacing: nil, at: now, revision: revision)
        let other = AppPlayerSession(notified: AppPlayerSnapshot(isPlaying: true, title: "U", trackID: "2"), replacing: first, at: now.addingTimeInterval(5), revision: revision)
        #expect(other.anchor == nil)
    }

    @Test func aReadAnchorsThePositionItSays() {
        let session = AppPlayerSession(read: AppPlayerSnapshot(isPlaying: true, title: "T", positionSeconds: 44.5), replacing: nil, at: now, revision: nextRevision())
        #expect(session.anchor == PlaybackAnchor(elapsedSeconds: 44.5, timestamp: now, rate: 1))
        #expect(AppPlayerSession(read: AppPlayerSnapshot(isPlaying: true, title: "T"), replacing: nil, at: now, revision: nextRevision()).anchor == nil)
    }

    @Test func theCoverIsKeptForTheSameTrackAndNewBytesGetANewRevision() {
        let revision = nextRevision()
        let bytes = Data([1, 2, 3])
        let first = AppPlayerSession(read: AppPlayerSnapshot(isPlaying: true, title: "T", trackID: "1", artwork: bytes), replacing: nil, at: now, revision: revision)
        #expect(first.artwork?.data == bytes)
        // The same track told again by a notification, which carries no cover: the cover stays, as the same image.
        let again = AppPlayerSession(notified: AppPlayerSnapshot(isPlaying: false, title: "T", trackID: "1"), replacing: first, at: now, revision: revision)
        #expect(again.artwork == first.artwork)
        // A read that carries the same bytes again is the same image too, not a new one to decode.
        let read = AppPlayerSession(read: AppPlayerSnapshot(isPlaying: true, title: "T", trackID: "1", artwork: bytes), replacing: again, at: now, revision: revision)
        #expect(read.artwork?.revision == first.artwork?.revision)
        // Another track, another cover; a track with none has none.
        let next = AppPlayerSession(read: AppPlayerSnapshot(isPlaying: true, title: "U", trackID: "2", artwork: Data([9])), replacing: read, at: now, revision: revision)
        #expect(next.artwork?.revision != first.artwork?.revision)
        #expect(AppPlayerSession(notified: AppPlayerSnapshot(isPlaying: true, title: "V", trackID: "3"), replacing: next, at: now, revision: revision).artwork == nil)
    }

    @Test func theStateIsTheAppsOwnAndHasNoModesOrLike() {
        let session = AppPlayerSession(
            read: AppPlayerSnapshot(isPlaying: true, title: "T", artist: "A", album: "B", durationSeconds: 100, positionSeconds: 5, trackID: "1"),
            replacing: nil, at: now, revision: nextRevision()
        )
        let state = session.state(bundleID: "com.apple.Music")
        #expect(state.bundleIdentifier == "com.apple.Music")
        #expect(state.parentApplicationBundleIdentifier == nil)
        #expect(state.title == "T" && state.artist == "A" && state.album == "B")
        #expect(state.durationSeconds == 100)
        #expect(state.isPlaying)
        #expect(state.shuffleMode == nil && state.repeatMode == nil && !state.supportsIsLiked)
        #expect(state.isActive)
        #expect(PlaybackClock.position(state, at: now.addingTimeInterval(3)) == 8)
    }

    @Test func sameTrackIsByIDWhenBothHaveOneElseByWords() {
        #expect(AppPlayerSnapshot(isPlaying: true, title: "A", trackID: "1").isSameTrack(as: AppPlayerSnapshot(isPlaying: false, title: "B", trackID: "1")))
        #expect(!AppPlayerSnapshot(isPlaying: true, title: "A", trackID: "1").isSameTrack(as: AppPlayerSnapshot(isPlaying: true, title: "A", trackID: "2")))
        #expect(AppPlayerSnapshot(isPlaying: true, title: "A", artist: "X").isSameTrack(as: AppPlayerSnapshot(isPlaying: false, title: "A", artist: "X", trackID: "9")))
        #expect(!AppPlayerSnapshot(isPlaying: true, title: "A", artist: "X").isSameTrack(as: AppPlayerSnapshot(isPlaying: true, title: "A", artist: "Y")))
    }
}
