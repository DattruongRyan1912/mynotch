import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
import YouTubeBridgeKit
@testable import MediaModule

@Suite struct MediaSourceHubTests {
    let environment = FakeAppEnvironment()
    let scheduler = ManualScheduler()
    let permissions = FakePermissionCenter()
    let music = FakeAppPlayerControl(.music)
    let spotify = FakeAppPlayerControl(.spotify)
    let hub: MediaSourceHub
    let clock = HubClock()

    init() {
        let clock = clock
        hub = MediaSourceHub(environment: environment.environment, controls: [music, spotify], now: { clock.date })
        // The fake says "denied" for what it was not told; the players have not been asked yet.
        allow(.music, .notDetermined)
        allow(.spotify, .notDetermined)
    }

    func start() {
        hub.start(scheduler: scheduler, permissions: permissions)
    }

    func allow(_ player: KnownPlayer, _ status: PermissionStatus = .granted) {
        permissions.statuses[.automation(bundleID: player.bundleID)] = status
    }

    /// Lets what the hub started on a task finish.
    func settle(until condition: () -> Bool = { false }) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func tab(_ id: Int = 1, title: String = "Page song", playing: Bool = true, time: Double = 10, artist: String? = nil, site: String = "music.example.com") -> BrowserTab {
        BrowserTab(tab: id, site: site, title: title, artist: artist, isPlaying: playing, time: time, duration: 200)
    }

    var ids: [MediaSourceID] { hub.book.entries.map(\.id) }

    // MARK: Music and Spotify tell what they play

    @Test func aPlayersNotificationMakesItASourceWithoutAnyAppleEventOrQuestion() {
        start()
        #expect(environment.observedNames == ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"])
        environment.music("Paused", name: "Song", artist: "Artist", album: "Album", totalTime: 200_000)
        #expect(ids == [.app("com.apple.Music")])
        let entry = hub.book.entries[0]
        #expect(entry.state.title == "Song" && entry.state.artist == "Artist" && entry.state.album == "Album")
        #expect(entry.state.durationSeconds == 200)
        #expect(!entry.state.isPlaying)
        #expect(!entry.isSystemBacked)
        #expect(entry.state.elapsedAnchor == nil, "Music's notification says nothing of the position")
        #expect(music.readCount == 0 && music.performed.isEmpty)
        #expect(permissions.requested.isEmpty)
    }

    @Test func aStoppedNotificationAndAQuitTakeTheSourceAway() {
        start()
        environment.music()
        environment.spotify()
        #expect(ids.count == 2)
        environment.music("Stopped")
        #expect(ids == [.app("com.spotify.client")])
        environment.quit("com.spotify.client")
        #expect(ids.isEmpty)
        environment.quit("com.apple.Music") // nothing there: nothing happens
        #expect(ids.isEmpty)
    }

    @Test func aPlayersNotificationThatIsNotOneOfItsIsIgnored() {
        start()
        environment.post(.music, [:])
        environment.post(.music, ["Player State": "Playing"])
        #expect(ids.isEmpty)
    }

    @Test func spotifysNotificationAnchorsThePositionItGives() {
        start()
        environment.spotify(position: 30)
        let state = hub.book.entries[0].state
        #expect(PlaybackClock.position(state, at: clock.date.addingTimeInterval(4)) == 34)
    }

    @Test func theSameTrackToldAgainDoesNotMoveThePlayer() {
        start()
        environment.spotify("Playing", position: 30)
        let before = hub.book.entries[0].state
        clock.advance(by: 2)
        environment.spotify("Playing", position: 32)
        #expect(hub.book.entries[0].state == before, "where the old anchor already puts it, within half a second")
        clock.advance(by: 2)
        environment.spotify("Playing", position: 80)
        #expect(hub.book.entries[0].state != before, "but a seek is news")
    }

    @Test func eachChangeTellsTheModuleAndThePlayerModelIsUpToDateWhenItDoes() {
        var changes: [MediaSourceHub.Change] = []
        hub.onChange = { change in changes.append(change) }
        start()
        changes.removeAll()
        environment.music()
        #expect(changes == [.other])
        #expect(hub.model.chips.map(\.id) == [.app("com.apple.Music")])
        hub.setSystem(NowPlayingState(bundleIdentifier: "org.videolan.vlc", title: "Movie", isPlaying: true))
        #expect(changes == [.other, .system])
        #expect(hub.model.chips.count == 2)
        #expect(hub.model.showsChips)
        #expect(hub.model.primaryID == .app("org.videolan.vlc"))
        #expect(hub.model.displayedID == .app("org.videolan.vlc"))
    }

    // MARK: tabs

    @Test func aTabIsASourceWithTheBrowsersIdentityAndItsSiteWhenItNamesNoArtist() {
        start()
        hub.receive(tab(7), connection: 3)
        #expect(ids == [.tab(TabRef(connection: 3, tab: 7))])
        let entry = hub.book.entries[0]
        #expect(entry.site == "music.example.com")
        #expect(entry.state.title == "Page song")
        #expect(entry.state.artist == "music.example.com")
        #expect(entry.state.playerBundleIdentifier == "com.google.Chrome")
        #expect(entry.state.isFromBrowser)
        #expect(entry.state.durationSeconds == 200)
        #expect(entry.state.isPlaying)
        hub.receive(tab(7, artist: "A real artist"), connection: 3)
        #expect(hub.book.entries[0].state.artist == "A real artist")
    }

    @Test func aPausedTabAndALiveStreamHaveNoMovingClockAndNoLength() {
        start()
        hub.receive(BrowserTab(tab: 1, site: "radio.example", title: "Live", isPlaying: false, time: 50, isLive: true), connection: 1)
        let state = hub.book.entries[0].state
        #expect(!state.isPlaying)
        #expect(state.durationSeconds == nil)
        #expect(state.elapsedAnchor?.rate == 0)
        hub.receive(BrowserTab(tab: 1, site: "radio.example", title: "Live", isPlaying: true, time: 50, rate: 1.5), connection: 1)
        #expect(hub.book.entries[0].state.elapsedAnchor?.rate == 1.5)
    }

    @Test func aReportThatFindsThePlayerWhereItWasIsNotNews() {
        start()
        hub.receive(tab(1, time: 10), connection: 1)
        let before = hub.book.entries[0].state
        clock.advance(by: 5)
        hub.receive(tab(1, time: 15), connection: 1)
        #expect(hub.book.entries[0].state == before)
        clock.advance(by: 5)
        hub.receive(tab(1, time: 70), connection: 1)
        #expect(hub.book.entries[0].state != before)
        let beforePause = hub.book.entries[0].state
        hub.receive(tab(1, playing: false, time: 70), connection: 1)
        #expect(hub.book.entries[0].state != beforePause)
    }

    @Test func twoChromesWithTheSameTabNumberAreTwoSourcesAndOneGoingTakesOnlyItsTabs() {
        start()
        hub.receive(tab(1, title: "One"), connection: 1)
        hub.receive(tab(1, title: "Two"), connection: 2)
        hub.receive(tab(2, title: "Three"), connection: 2)
        #expect(ids.count == 3)
        hub.connectionEnded(2)
        #expect(ids == [.tab(TabRef(connection: 1, tab: 1))])
        hub.connectionEnded(2)
        hub.tabGone(1, connection: 1)
        #expect(ids.isEmpty)
        hub.tabGone(1, connection: 1)
    }

    @Test func aTabNotHeardFromForTheLiveWindowGoesAndOnlyThenOneTimerSleepsUntilItAndNoneRunsWithoutTabs() {
        start()
        #expect(scheduler.pendingCount == 0)
        hub.receive(tab(1), connection: 1)
        #expect(scheduler.pendingCount == 1, "one timer, for the tab that goes stale first")
        hub.receive(tab(2, title: "Other"), connection: 1)
        #expect(scheduler.pendingCount == 1)
        scheduler.advance(by: .seconds(MediaSourceBook.tabLiveWindow - 1))
        #expect(ids.count == 2)
        scheduler.advance(by: .seconds(2))
        #expect(ids.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func aTabThatKeepsReportingIsKept() {
        start()
        hub.receive(tab(1), connection: 1)
        for _ in 0..<5 {
            clock.advance(by: 100)
            scheduler.advance(by: .seconds(100))
            hub.receive(tab(1, time: 10), connection: 1)
        }
        #expect(ids.count == 1)
    }

    @Test func forgettingTheTabsWhenTheBridgeIsOffTakesThemAllAndTheirTimer() {
        start()
        hub.receive(tab(1), connection: 1)
        hub.receive(tab(2, title: "B"), connection: 2)
        hub.forgetTabs()
        #expect(ids.isEmpty)
        #expect(scheduler.pendingCount == 0)
        hub.forgetTabs()
    }

    // MARK: the system's session

    @Test func theSystemsSessionOfAnAppItIsReadingIsMergedIntoOneSource() {
        start()
        environment.music("Paused", name: "Song")
        hub.setSystem(NowPlayingState(bundleIdentifier: "com.apple.Music", title: "Song", isPlaying: true))
        #expect(ids == [.app("com.apple.Music")])
        #expect(hub.book.entries[0].isSystemBacked)
        #expect(hub.book.entries[0].isPlaying)
        hub.setSystem(nil)
        #expect(ids == [.app("com.apple.Music")])
        #expect(!hub.book.entries[0].isSystemBacked)
    }

    // MARK: Apple Events: nothing runs while hidden

    @Test func nothingRunsWhileTheTabIsHiddenAndNoAppThatOnlyAppleEventsCanReadIsFollowedWhilePlaying() async {
        allow(.music)
        allow(.spotify)
        environment.running = [KnownPlayer.music.bundleID, KnownPlayer.spotify.bundleID]
        start()
        environment.music("Paused")
        environment.spotify("Paused")
        await settle()
        scheduler.advance(by: .seconds(30))
        await settle()
        #expect(scheduler.pendingCount == 0, "no timer at all")
        #expect(music.readCount == 0 && spotify.readCount == 0, "and no Apple Event")
        #expect(permissions.requested.isEmpty)
    }

    @Test func whileTheTabIsVisibleTheAppsThatRunAndAreAllowedAreReadNowAndOnceASecond() async {
        allow(.music)
        allow(.spotify, .notDetermined)
        environment.running = [KnownPlayer.music.bundleID, KnownPlayer.spotify.bundleID]
        music.readings = [.snapshot(AppPlayerSnapshot(isPlaying: false, title: "Song", positionSeconds: 5))]
        start()
        hub.model.setTabVisible(true)
        await settle { music.readCount == 1 }
        #expect(music.readCount == 1, "at once, not after a second")
        #expect(spotify.readCount == 0, "Spotify was not allowed yet, and nobody asked")
        #expect(permissions.requested.isEmpty, "looking at the tab is no reason to ask")
        #expect(scheduler.pendingCount == 1)
        for second in 2...4 {
            scheduler.advance(by: .seconds(1))
            await settle { music.readCount == second }
        }
        #expect(music.readCount == 4)
        #expect(ids == [.app("com.apple.Music")])
        hub.model.setTabVisible(false)
        #expect(scheduler.pendingCount == 0, "hiding the tab stops it")
        scheduler.advance(by: .seconds(10))
        await settle()
        #expect(music.readCount == 4)
    }

    @Test func anAppThatIsNotRunningIsNeverReadAndOneThatQuitIsLetGo() async {
        allow(.music)
        start()
        hub.model.setTabVisible(true)
        scheduler.advance(by: .seconds(5))
        await settle()
        #expect(music.readCount == 0)
        #expect(scheduler.pendingCount == 0)
        environment.running = [KnownPlayer.music.bundleID]
        environment.music("Playing")
        hub.model.setTabVisible(false)
        hub.model.setTabVisible(true)
        await settle { music.readCount == 1 }
        #expect(music.readCount == 1)
        environment.running = []
        scheduler.advance(by: .seconds(5))
        await settle()
        #expect(music.readCount == 1, "it quit: no more reads")
    }

    @Test func anAppTheSystemAlreadyPlaysIsNotReadByAppleEventsAtAll() async {
        allow(.music)
        environment.running = [KnownPlayer.music.bundleID]
        start()
        hub.setSystem(NowPlayingState(bundleIdentifier: "com.apple.Music", title: "Song", isPlaying: true))
        hub.model.setTabVisible(true)
        scheduler.advance(by: .seconds(5))
        await settle()
        #expect(music.readCount == 0, "its session is the source: the system says all there is")
        #expect(scheduler.pendingCount == 0)
        hub.setSystem(nil)
        environment.music("Paused")
        scheduler.advance(by: .seconds(1))
        await settle { music.readCount == 1 }
        #expect(music.readCount == 1, "once the system stops, Apple Events fill in what only they can")
    }

    @Test func whileHiddenOnlyTheAppThatTheNotchFollowsIsRead() async {
        allow(.music)
        allow(.spotify)
        environment.running = [KnownPlayer.music.bundleID, KnownPlayer.spotify.bundleID]
        start()
        environment.music("Paused")
        environment.spotify("Playing")
        #expect(hub.book.primaryID == .app("com.spotify.client"))
        scheduler.advance(by: .seconds(1))
        await settle { spotify.readCount >= 1 }
        #expect(spotify.readCount >= 1)
        #expect(music.readCount == 0, "Music is not what the notch follows, and the tab is hidden")
        let spotifyReads = spotify.readCount
        // Music plays and is pinned: now it is the one the notch follows.
        environment.music("Playing")
        hub.togglePin(.app("com.apple.Music"))
        #expect(hub.book.primaryID == .app("com.apple.Music"))
        scheduler.advance(by: .seconds(1))
        await settle { music.readCount >= 1 }
        #expect(music.readCount >= 1)
        scheduler.advance(by: .seconds(1))
        await settle()
        #expect(spotify.readCount == spotifyReads, "and now the other way round")
    }

    @Test func aReadThatIsStillOnItsWayIsNotStartedAgain() async {
        allow(.music)
        environment.running = [KnownPlayer.music.bundleID]
        let release = Release()
        music.gate = { await release.wait() }
        start()
        hub.model.setTabVisible(true)
        await settle { music.readCount == 1 }
        scheduler.advance(by: .seconds(3))
        await settle()
        #expect(music.readCount == 1, "it has not answered: no second read on top of it")
        await release.open()
        await settle()
        scheduler.advance(by: .seconds(1))
        await settle { music.readCount >= 2 }
        #expect(music.readCount >= 2)
    }

    @Test func aReadMakesTheSourceAndAKeepingItWhereItIsChangesNothingAndStoppedOrNotRunningTakesItAway() async {
        allow(.music)
        environment.running = [KnownPlayer.music.bundleID]
        let snapshot = AppPlayerSnapshot(isPlaying: true, title: "Song", durationSeconds: 200, positionSeconds: 20, trackID: "1")
        music.readings = [.snapshot(snapshot)]
        start()
        hub.model.setTabVisible(true)
        await settle { !ids.isEmpty }
        let first = hub.book.entries[0].state
        #expect(first.title == "Song")
        #expect(PlaybackClock.position(first, at: clock.date.addingTimeInterval(1)) == 21)
        clock.advance(by: 1)
        var next = snapshot
        next.positionSeconds = 21
        music.readings = [.snapshot(next)]
        scheduler.advance(by: .seconds(1))
        await settle { music.readCount >= 2 }
        await settle()
        #expect(hub.book.entries[0].state == first, "the player was where it was: nothing for the views")
        music.readings = [.stopped]
        scheduler.advance(by: .seconds(1))
        await settle { ids.isEmpty }
        #expect(ids.isEmpty)
    }

    @Test func aReadThatFailsChangesNothing() async {
        allow(.music)
        environment.running = [KnownPlayer.music.bundleID]
        start()
        environment.music("Playing")
        music.readings = [.failed]
        hub.model.setTabVisible(true)
        await settle { music.readCount >= 1 }
        await settle()
        #expect(ids == [.app("com.apple.Music")])
    }

    // MARK: Apple Events: the user's say

    @Test func theFirstTimeTheUserTakesAnAppsChipTheyAreAskedAndOnlyThen() async {
        allow(.music, .notDetermined)
        environment.running = [KnownPlayer.music.bundleID]
        permissions.requestResult = .granted
        start()
        environment.music("Paused")
        environment.spotify("Playing")
        #expect(permissions.requested.isEmpty, "nothing was asked for the notifications, nor for the sources being listed")
        hub.select(.app("com.apple.Music"))
        await settle { !permissions.requested.isEmpty }
        #expect(permissions.requested == [.automation(bundleID: "com.apple.Music")], "the app whose chip it was, and no other")
        hub.select(.app("com.spotify.client"))
        await settle { permissions.requested.count == 2 }
        hub.select(.app("com.apple.Music"))
        hub.select(.app("com.spotify.client"))
        await settle()
        #expect(permissions.requested.count == 2, "each app is asked once")
    }

    @Test func anAnswerOfYesLetsTheAppBeReadAndNoHidesItAndNamesItInSettings() async {
        environment.running = [KnownPlayer.music.bundleID, KnownPlayer.spotify.bundleID]
        allow(.music, .notDetermined)
        allow(.spotify, .notDetermined)
        permissions.requestResult = .granted
        start()
        environment.music("Paused")
        environment.spotify("Playing")
        hub.select(.app("com.apple.Music"))
        await settle { permissions.statuses[.automation(bundleID: "com.apple.Music")] == .granted }
        #expect(hub.model.deniedApps.isEmpty)
        // The next one is refused.
        permissions.requestResult = .denied
        permissions.statuses[.automation(bundleID: "com.spotify.client")] = .notDetermined
        hub.select(.app("com.spotify.client"))
        await settle { hub.model.deniedApps == ["Spotify"] }
        #expect(hub.model.deniedApps == ["Spotify"])
        #expect(ids == [.app("com.apple.Music")], "Spotify, which the user refused, is hidden")
        #expect(hub.model.chips.map(\.id) == [.app("com.apple.Music")])
    }

    @Test func aRefusalHidesOnlyWhatTheAppSaysOfItselfNotTheSystemsSessionForIt() async {
        environment.running = [KnownPlayer.music.bundleID]
        allow(.music, .denied)
        start()
        environment.music("Paused")
        await settle()
        #expect(ids.isEmpty, "nothing of what Music says of itself is shown")
        #expect(hub.model.deniedApps == ["Music"], "the permission was refused before: Settings says so from the start")
        hub.setSystem(NowPlayingState(bundleIdentifier: "com.apple.Music", title: "Playing now", isPlaying: true))
        #expect(ids == [.app("com.apple.Music")])
        #expect(hub.book.entries[0].isSystemBacked, "its session is the system's, and is controlled through the system")
        hub.setSystem(nil)
        #expect(ids.isEmpty)
    }

    @Test func aRefusalIsNeverAskedAgainAndAPermissionGivenInSettingsIsSeenWhenTheTabIsOpened() async {
        environment.running = [KnownPlayer.music.bundleID]
        allow(.music, .denied)
        start()
        environment.music("Paused")
        hub.select(.app("com.apple.Music"))
        await settle()
        #expect(permissions.requested.isEmpty)
        // The user allows it in System Settings: the next time the tab is opened the app is back.
        allow(.music, .granted)
        hub.model.setTabVisible(true)
        #expect(hub.model.deniedApps.isEmpty)
        await settle { !ids.isEmpty }
        #expect(ids == [.app("com.apple.Music")])
    }

    @Test func aReadThatMacOSRefusesHidesTheAppToo() async {
        environment.running = [KnownPlayer.music.bundleID]
        allow(.music)
        start()
        environment.music("Playing")
        music.readings = [.notAllowed]
        hub.model.setTabVisible(true)
        await settle { hub.model.deniedApps == ["Music"] }
        #expect(hub.model.deniedApps == ["Music"])
        #expect(ids.isEmpty)
        scheduler.advance(by: .seconds(5))
        await settle()
        #expect(music.readCount == 1, "and it is read no more")
    }

    @Test func noQuestionIsAskedForAnAppThatIsNotRunning() async {
        allow(.music, .notDetermined)
        start()
        environment.music("Paused")
        environment.running = []
        hub.select(.app("com.apple.Music"))
        await settle()
        #expect(permissions.requested.isEmpty)
    }

    // MARK: commands to an app

    @Test func aCommandToAnAppAsksTheFirstTimeThenDoesItAndReadsToShowWhatItDid() async {
        environment.running = [KnownPlayer.music.bundleID]
        allow(.music, .notDetermined)
        permissions.requestResult = .granted
        start()
        environment.music("Paused")
        hub.perform(.togglePlayPause, onApp: "com.apple.Music")
        await settle { !music.performed.isEmpty }
        #expect(permissions.requested == [.automation(bundleID: "com.apple.Music")])
        #expect(music.performed == [.togglePlayPause])
        await settle { music.readCount >= 1 }
        #expect(music.readCount >= 1, "a read follows, so that the player shows what happened")
        hub.perform(.next, onApp: "com.apple.Music")
        await settle { music.performed.count == 2 }
        #expect(permissions.requested.count == 1, "asked once")
    }

    @Test func aCommandToAnAppTheUserRefusedOrThatIsNotRunningDoesNothing() async {
        environment.running = [KnownPlayer.music.bundleID]
        allow(.music, .denied)
        start()
        hub.perform(.play, onApp: "com.apple.Music")
        await settle()
        #expect(music.performed.isEmpty)
        allow(.music, .granted)
        environment.running = []
        hub.perform(.play, onApp: "com.apple.Music")
        await settle()
        #expect(music.performed.isEmpty, "not running: never started")
        hub.perform(.play, onApp: "org.videolan.vlc")
        await settle()
    }

    @Test func aCommandThatMacOSRefusesHidesTheAppAndOneToAnAppThatQuitTakesItAway() async {
        environment.running = [KnownPlayer.music.bundleID, KnownPlayer.spotify.bundleID]
        allow(.music)
        allow(.spotify)
        start()
        environment.music("Paused")
        environment.spotify("Paused")
        music.outcome = .notAllowed
        hub.perform(.play, onApp: "com.apple.Music")
        await settle { hub.model.deniedApps == ["Music"] }
        #expect(hub.model.deniedApps == ["Music"])
        spotify.outcome = .notRunning
        hub.perform(.play, onApp: "com.spotify.client")
        await settle { ids.isEmpty }
        #expect(ids.isEmpty)
    }

    // MARK: stopping

    @Test func stoppingLetsGoOfEverythingAndForgetsWhatTheUserChose() async {
        allow(.music)
        environment.running = [KnownPlayer.music.bundleID]
        start()
        environment.music("Playing")
        hub.receive(tab(1), connection: 1)
        hub.togglePin(.app("com.apple.Music"))
        hub.model.setTabVisible(true)
        await settle()
        #expect(environment.observerCount > 0)
        hub.stop()
        #expect(environment.observerCount == 0)
        #expect(scheduler.pendingCount == 0)
        #expect(hub.book.entries.isEmpty)
        #expect(hub.book.pinnedID == nil)
        #expect(hub.model.chips.isEmpty)
        #expect(!hub.model.isTabVisible)
        environment.music("Playing") // nobody listens
        #expect(hub.book.entries.isEmpty)
    }

    @Test func anAnswerThatWasOnItsWayWhenTheHubStoppedIsIgnored() async {
        allow(.music)
        environment.running = [KnownPlayer.music.bundleID]
        let release = Release()
        music.gate = { await release.wait() }
        music.readings = [.snapshot(AppPlayerSnapshot(isPlaying: true, title: "Late"))]
        start()
        hub.model.setTabVisible(true)
        await settle { music.readCount == 1 }
        hub.stop()
        await release.open()
        await settle()
        #expect(hub.book.entries.isEmpty)
    }

    @Test func startingAgainStartsFromNothing() {
        start()
        environment.music("Playing")
        start()
        #expect(hub.book.entries.isEmpty)
        #expect(environment.observerCount == 3, "two players and the quit, not twice")
    }

    // MARK: what the user does

    @Test func theModelsActionsReachTheHub() {
        start()
        environment.music("Playing")
        environment.spotify("Paused")
        hub.model.select(.app("com.spotify.client"))
        #expect(hub.book.displayedID == .app("com.spotify.client"))
        hub.model.togglePin(.app("com.spotify.client"))
        #expect(hub.book.pinnedID == .app("com.spotify.client"))
        #expect(hub.model.chips.first { $0.id == .app("com.spotify.client") }?.isPinned == true)
        hub.model.togglePin(.app("com.spotify.client"))
        #expect(hub.book.pinnedID == nil)
    }

    @Test func theChipsAreTheSourcesInOrderWithTheirMarks() {
        start()
        environment.music("Paused", name: "Old")
        environment.spotify("Playing", name: "New")
        let chips = hub.model.chips
        #expect(chips.map(\.title) == ["New", "Old"])
        #expect(chips.map(\.isPlaying) == [true, false])
        #expect(chips.map(\.isPrimary) == [true, false])
        #expect(chips.map(\.isShown) == [true, false])
        #expect(chips.map(\.iconBundleID) == ["com.spotify.client", "com.apple.Music"])
        hub.receive(tab(4, site: "radio.example"), connection: 1)
        #expect(hub.model.chips.first { $0.id == .tab(TabRef(connection: 1, tab: 4)) }?.iconBundleID == "com.google.Chrome")
        #expect(hub.model.chips.first { $0.id == .tab(TabRef(connection: 1, tab: 4)) }?.detail == "radio.example")
    }
}

final class HubClock {
    private(set) var date = Date(timeIntervalSince1970: 2_000_000)

    func advance(by seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

/// A gate a test opens when the read that waits on it may answer.
actor Release {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}
