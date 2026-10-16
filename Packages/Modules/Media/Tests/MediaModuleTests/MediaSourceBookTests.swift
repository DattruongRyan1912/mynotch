import Foundation
import Testing
@testable import MediaModule

@Suite struct MediaSourceBookTests {
    static let music = "com.apple.Music"
    static let spotify = "com.spotify.client"
    static let chrome = "com.google.Chrome"
    let start = Date(timeIntervalSince1970: 1_000_000)
    var book = MediaSourceBook()

    static func state(_ bundle: String, _ title: String = "Song", playing: Bool = true, artwork: Bool = false) -> NowPlayingState {
        NowPlayingState(
            bundleIdentifier: bundle, title: title, artist: "Artist", isPlaying: playing,
            artwork: artwork ? ArtworkData(data: Data([1, 2, 3]), mimeType: "image/png", revision: 1) : nil
        )
    }

    /// What the system says when a Chrome tab plays: the helper process, with Chrome as its parent.
    static func chromeSession(_ title: String = "Song", playing: Bool = true) -> NowPlayingState {
        var state = Self.state("com.google.Chrome.helper", title, playing: playing)
        state.parentApplicationBundleIdentifier = chrome
        return state
    }

    static func tabState(_ title: String = "Song", playing: Bool = true) -> NowPlayingState {
        var state = Self.state(chrome, title, playing: playing)
        state.parentApplicationBundleIdentifier = chrome
        return state
    }

    func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    var ids: [MediaSourceID] { book.entries.map(\.id) }

    // MARK: the system's session

    @Test mutating func theSystemsSessionAloneIsOneSourceAndThePrimary() {
        book.setSystem(Self.state(Self.music), at: at(0))
        #expect(ids == [.app(Self.music)])
        #expect(book.primaryID == .app(Self.music))
        #expect(book.entries[0].isSystemBacked)
        #expect(book.entries[0].app == Self.music)
        #expect(book.displayedID == .app(Self.music))
    }

    @Test mutating func aSessionWithNoTitleIsNoSourceAndNothingPlayingLeavesNone() {
        book.setSystem(NowPlayingState(bundleIdentifier: Self.music, title: ""), at: at(0))
        #expect(book.entries.isEmpty)
        #expect(book.primaryID == nil)
        book.setSystem(Self.state(Self.music), at: at(1))
        book.setSystem(nil, at: at(2))
        #expect(book.entries.isEmpty)
        #expect(book.primaryID == nil)
        #expect(book.displayed == nil)
    }

    // MARK: merging

    @Test mutating func theSystemsSessionOfAnAppIsMergedWithTheAppsOwnByBundleIDAlone() {
        book.setApp(Self.music, state: Self.state(Self.music, "Old title", playing: false, artwork: true), at: at(0))
        book.setSystem(Self.state(Self.music, "New title"), at: at(1))
        #expect(ids == [.app(Self.music)], "one source, not two, though the titles differ for a moment at a track change")
        let entry = book.entries[0]
        #expect(entry.isSystemBacked)
        #expect(entry.state.title == "New title", "the system's state is the richer one")
        #expect(entry.state.isPlaying)
        #expect(entry.state.artwork?.data == Data([1, 2, 3]), "but a cover only the app has is not lost")
    }

    @Test mutating func whenTheSystemsSessionEndsTheAppsOwnSourceStaysAsItReportedItself() {
        book.setApp(Self.music, state: Self.state(Self.music, "Song", playing: false), at: at(0))
        book.setSystem(Self.state(Self.music, "Song"), at: at(1))
        #expect(book.entries[0].isSystemBacked)
        book.setSystem(nil, at: at(2))
        #expect(ids == [.app(Self.music)])
        #expect(!book.entries[0].isSystemBacked)
        #expect(!book.entries[0].isPlaying)
    }

    @Test mutating func twoAppsAreTwoSourcesAndEachKeepsItsOwnID() {
        book.setApp(Self.music, state: Self.state(Self.music, "A", playing: false), at: at(0))
        book.setSystem(Self.state(Self.spotify, "B"), at: at(1))
        #expect(Set(ids) == [.app(Self.music), .app(Self.spotify)])
        #expect(book.primaryID == .app(Self.spotify))
        #expect(book.entry(.app(Self.music))?.isSystemBacked == false)
        #expect(book.entry(.app(Self.spotify))?.isSystemBacked == true)
    }

    @Test mutating func aSessionOfAnAppNobodyElseReportsIsASourceOfItsOwn() {
        book.setSystem(Self.state("org.videolan.vlc", "Movie"), at: at(0))
        #expect(ids == [.app("org.videolan.vlc")])
        #expect(book.entries[0].isSystemBacked)
    }

    @Test mutating func theSystemsBrowserSessionIsMergedWithTheTabThatHasItsTitle() {
        let ref = TabRef(connection: 4, tab: 11)
        book.setTab(ref, state: Self.tabState("My Song", playing: true), site: "music.example.com", at: at(0))
        book.setSystem(Self.chromeSession("my   song"), at: at(1))
        #expect(ids == [.tab(ref)], "one source: the titles are the same once normalised")
        #expect(book.entries[0].isSystemBacked)
        #expect(book.entries[0].tab == ref)
        #expect(book.entries[0].site == "music.example.com")
        #expect(book.entries[0].state.bundleIdentifier == "com.google.Chrome.helper", "the system's own state")
    }

    @Test mutating func aBrowserSessionNoTabAccountsForIsTheBrowsersOwnSource() {
        book.setTab(TabRef(connection: 1, tab: 1), state: Self.tabState("Another", playing: false), at: at(0))
        book.setSystem(Self.chromeSession("Not a tab we know"), at: at(1))
        #expect(Set(ids) == [.app(Self.chrome), .tab(TabRef(connection: 1, tab: 1))])
        #expect(book.entry(.app(Self.chrome))?.isSystemBacked == true)
    }

    @Test mutating func aBrowserSessionWhoseTitleDiffersIsTheOnlyTabThatPlaysWhenExactlyOneDoes() {
        // A page and Chrome may word one title two ways (and differ for a moment as a video changes): not two chips.
        let playing = TabRef(connection: 1, tab: 1)
        book.setTab(playing, state: Self.tabState("(3) Inbox - Mail", playing: true), at: at(0))
        book.setTab(TabRef(connection: 1, tab: 2), state: Self.tabState("Paused page", playing: false), at: at(0))
        book.setSystem(Self.chromeSession("Inbox - Mail"), at: at(1))
        #expect(book.entries.count == 2)
        #expect(book.entry(.tab(playing))?.isSystemBacked == true)
        #expect(book.entry(.app(Self.chrome)) == nil)
    }

    @Test mutating func withTwoTabsPlayingOrNoneADifferingTitleIsNotGuessed() {
        book.setTab(TabRef(connection: 1, tab: 1), state: Self.tabState("One", playing: true), at: at(0))
        book.setTab(TabRef(connection: 1, tab: 2), state: Self.tabState("Two", playing: true), at: at(0))
        book.setSystem(Self.chromeSession("Neither"), at: at(1))
        #expect(book.entries.count == 3)
        #expect(book.entry(.app(Self.chrome))?.isSystemBacked == true)
        var none = MediaSourceBook()
        none.setTab(TabRef(connection: 1, tab: 1), state: Self.tabState("One", playing: false), at: at(0))
        none.setSystem(Self.chromeSession("Neither"), at: at(1))
        #expect(none.entries.count == 2)
        #expect(none.entry(.app(Self.chrome)) != nil)
    }

    @Test mutating func aTitleThatMatchesIsPreferredToTheOneTabThatPlays() {
        let matching = TabRef(connection: 1, tab: 1)
        book.setTab(matching, state: Self.tabState("Same", playing: false), at: at(0))
        book.setTab(TabRef(connection: 1, tab: 2), state: Self.tabState("Other", playing: true), at: at(0))
        book.setSystem(Self.chromeSession("Same"), at: at(1))
        #expect(book.entry(.tab(matching))?.isSystemBacked == true)
    }

    @Test mutating func ofTwoTabsWithOneTitleTheOneThatPlaysThenTheOneHeardFromLastIsTheSystems() {
        let paused = TabRef(connection: 1, tab: 1)
        let playing = TabRef(connection: 1, tab: 2)
        let newer = TabRef(connection: 1, tab: 3)
        book.setTab(paused, state: Self.tabState("Same", playing: false), at: at(0))
        book.setTab(playing, state: Self.tabState("Same", playing: true), at: at(1))
        book.setSystem(Self.chromeSession("Same"), at: at(2))
        #expect(book.entry(.tab(playing))?.isSystemBacked == true)
        #expect(book.entry(.tab(paused))?.isSystemBacked == false)

        book.setTab(playing, state: Self.tabState("Same", playing: false), at: at(3))
        book.setTab(newer, state: Self.tabState("Same", playing: false), at: at(4))
        book.setTab(paused, state: Self.tabState("Same", playing: false), at: at(5))
        #expect(book.entry(.tab(paused))?.isSystemBacked == true, "none plays: the one heard from last")
        #expect(book.entries.filter(\.isSystemBacked).count == 1)
    }

    @Test mutating func twoChromesWithTheSameTabNumberAreTwoSources() {
        book.setTab(TabRef(connection: 1, tab: 7), state: Self.tabState("One"), at: at(0))
        book.setTab(TabRef(connection: 2, tab: 7), state: Self.tabState("Two"), at: at(1))
        #expect(ids.count == 2)
        #expect(MediaSourceID.tab(TabRef(connection: 1, tab: 7)) != MediaSourceID.tab(TabRef(connection: 2, tab: 7)))
    }

    @Test mutating func aBrowserSessionIsNeverMergedWithAnAppOnlyBecauseTheTitleMatches() {
        book.setApp(Self.music, state: Self.state(Self.music, "Same", playing: false), at: at(0))
        book.setSystem(Self.chromeSession("Same"), at: at(1))
        #expect(Set(ids) == [.app(Self.music), .app(Self.chrome)])
    }

    // MARK: the primary source, automatic

    @Test mutating func theSourceThatStartedPlayingMostRecentlyIsThePrimary() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        #expect(book.primaryID == .app(Self.music))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(5))
        #expect(book.primaryID == .app(Self.spotify))
        // Music going on playing, or being told of again, does not make it the latest.
        book.setApp(Self.music, state: Self.state(Self.music, "Song 2"), at: at(6))
        #expect(book.primaryID == .app(Self.spotify))
    }

    @Test mutating func aSourceThatPausesAndPlaysAgainIsTheLatestToStart() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(5))
        book.setApp(Self.music, state: Self.state(Self.music, playing: false), at: at(6))
        book.setApp(Self.music, state: Self.state(Self.music, playing: true), at: at(7))
        #expect(book.primaryID == .app(Self.music))
    }

    @Test mutating func pausingTheOnlySourceKeepsItAsThePrimary() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.music, state: Self.state(Self.music, playing: false), at: at(1))
        #expect(book.primaryID == .app(Self.music))
        #expect(book.primary?.isPlaying == false)
    }

    @Test mutating func pausingThePrimaryNeverSwapsItForASourceThatIsNotPlaying() {
        book.setApp(Self.spotify, state: Self.state(Self.spotify, playing: false), at: at(0))
        book.setApp(Self.music, state: Self.state(Self.music), at: at(1))
        book.setApp(Self.music, state: Self.state(Self.music, playing: false), at: at(2))
        #expect(book.primaryID == .app(Self.music))
        // A paused source that starts before the primary has paused does not take the place either.
        book.setApp(Self.spotify, state: Self.state(Self.spotify, "Another", playing: false), at: at(3))
        #expect(book.primaryID == .app(Self.music))
    }

    @Test mutating func pausingThePrimaryHandsItToTheSourceThatPlays() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(5))
        book.setApp(Self.spotify, state: Self.state(Self.spotify, playing: false), at: at(6))
        #expect(book.primaryID == .app(Self.music), "Music still plays")
        book.setApp(Self.music, state: Self.state(Self.music, playing: false), at: at(7))
        #expect(book.primaryID == .app(Self.music), "nothing plays now, and the primary stays")
    }

    @Test mutating func aSourceThatGoesAwayHandsThePlaceOnAndAnEmptyBookHasNone() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(5))
        #expect(book.primaryID == .app(Self.spotify))
        book.setApp(Self.spotify, state: nil, at: at(6))
        #expect(book.primaryID == .app(Self.music))
        book.setApp(Self.music, state: nil, at: at(7))
        #expect(book.primaryID == nil)
        #expect(book.entries.isEmpty)
    }

    @Test mutating func whenThePrimaryGoesAwayWithNothingPlayingTheSourceThatPlayedLastTakesTheirPlace() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(5))
        book.setApp(Self.music, state: Self.state(Self.music, playing: false), at: at(8))
        book.setApp(Self.spotify, state: Self.state(Self.spotify, playing: false), at: at(9))
        book.setTab(TabRef(connection: 1, tab: 1), state: Self.tabState("Tab", playing: false), at: at(20))
        #expect(book.primaryID == .app(Self.spotify), "a paused source does not take the place from the primary")
        book.setApp(Self.spotify, state: nil, at: at(21))
        #expect(book.primaryID == .app(Self.music), "Music played after the tab was last seen paused")
    }

    @Test mutating func aSourceThatStartsAtTheSameMomentAsAnotherIsChosenWithoutDependingOnTheOrderOfAnything() {
        // The system's session wins a tie; otherwise the id decides.
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setSystem(Self.state(Self.spotify), at: at(0))
        #expect(book.primaryID == .app(Self.spotify))
        var other = MediaSourceBook()
        other.setSystem(Self.state(Self.spotify), at: at(0))
        other.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        #expect(other.primaryID == .app(Self.spotify))
        var apps = MediaSourceBook()
        apps.setApp("com.b", state: Self.state("com.b"), at: at(0))
        apps.setApp("com.a", state: Self.state("com.a"), at: at(0))
        #expect(apps.primaryID == .app("com.a"))
    }

    // MARK: pinned

    @Test mutating func aPinnedSourceStaysThePrimaryWhateverStartsAfterItAndWhateverItDoes() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.pin(.app(Self.music), at: at(1))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(5))
        #expect(book.primaryID == .app(Self.music))
        book.setApp(Self.music, state: Self.state(Self.music, playing: false), at: at(6))
        #expect(book.primaryID == .app(Self.music), "paused, with another source playing")
        #expect(book.pinnedID == .app(Self.music))
    }

    @Test mutating func thePinIsReleasedWhenThatSourceHasBeenAwayForTheGraceAndNotBefore() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(1))
        book.pin(.app(Self.music), at: at(2))
        book.setApp(Self.music, state: nil, at: at(3))
        // Still pinned, with what it last was: it may only be a blink.
        #expect(book.pinnedID == .app(Self.music))
        #expect(book.primaryID == .app(Self.music))
        #expect(book.nextExpiry == at(3 + MediaSourceBook.releaseGrace))
        book.expireTabs(at: at(3 + MediaSourceBook.releaseGrace - 0.1))
        #expect(book.pinnedID == .app(Self.music))
        book.expireTabs(at: at(3 + MediaSourceBook.releaseGrace))
        #expect(book.pinnedID == nil)
        #expect(book.primaryID == .app(Self.spotify))
        #expect(book.nextExpiry == nil)
        // When it comes back it is not pinned any more: the user's choice was for that source's life.
        book.setApp(Self.music, state: Self.state(Self.music), at: at(10))
        #expect(book.pinnedID == nil)
        #expect(book.primaryID == .app(Self.music), "the latest to start, as with any other")
    }

    @Test mutating func aPinnedSourceThatBlinksOutAndBackKeepsItsPinAndTheNotchDoesNotFlip() {
        // The system's session is empty for a moment between two tracks. Something else plays meanwhile.
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setSystem(Self.state("org.videolan.vlc", "Movie"), at: at(1))
        book.pin(.app("org.videolan.vlc"), at: at(2))
        #expect(book.primaryID == .app("org.videolan.vlc"))
        book.setSystem(nil, at: at(3))
        #expect(book.primaryID == .app("org.videolan.vlc"), "it did not go: the notch stays where it was, with what it last showed")
        #expect(book.primary?.state.title == "Movie")
        #expect(book.pinnedID == .app("org.videolan.vlc"))
        book.setSystem(Self.state("org.videolan.vlc", "Next movie"), at: at(3.3))
        #expect(book.pinnedID == .app("org.videolan.vlc"))
        #expect(book.primaryID == .app("org.videolan.vlc"))
        #expect(book.primary?.state.title == "Next movie", "and now it is live again, with the new track")
        #expect(book.nextExpiry == nil, "nothing is missing any more")
        book.expireTabs(at: at(20))
        #expect(book.pinnedID == .app("org.videolan.vlc"))
    }

    @Test mutating func aBlinkingSourceThatWasNeitherPinnedNorChosenIsGoneAtOnce() {
        book.setSystem(Self.state("org.videolan.vlc", "Movie"), at: at(0))
        book.setSystem(nil, at: at(1))
        #expect(book.entries.isEmpty)
        #expect(book.nextExpiry == nil)
    }

    @Test mutating func unpinningReturnsToTheAutomaticChoiceAndPinningAnotherMovesThePin() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(1))
        book.pin(.app(Self.music), at: at(2))
        book.pin(.app(Self.spotify), at: at(3))
        #expect(book.pinnedID == .app(Self.spotify))
        book.togglePin(.app(Self.spotify), at: at(4))
        #expect(book.pinnedID == nil)
        book.togglePin(.app(Self.music), at: at(5))
        #expect(book.primaryID == .app(Self.music))
        book.unpin(at: at(6))
        #expect(book.primaryID == .app(Self.spotify))
        book.unpin(at: at(7))
    }

    @Test mutating func aSourceThatIsNotThereCannotBePinned() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.pin(.app(Self.spotify), at: at(1))
        #expect(book.pinnedID == nil)
        #expect(book.primaryID == .app(Self.music))
    }

    @Test mutating func aPinnedSourceMergedWithTheSystemKeepsItsPinThroughTheMerge() {
        // The system's session for Music arrives after Music was pinned from what it said of itself: still one source, still pinned.
        book.setApp(Self.music, state: Self.state(Self.music, playing: false), at: at(0))
        book.pin(.app(Self.music), at: at(1))
        book.setSystem(Self.state(Self.spotify), at: at(2))
        #expect(book.primaryID == .app(Self.music))
        book.setSystem(Self.state(Self.music), at: at(3))
        #expect(book.pinnedID == .app(Self.music))
        #expect(book.primaryID == .app(Self.music))
        #expect(ids == [.app(Self.music)])
    }

    // MARK: the chips

    @Test mutating func theChipsListThePrimaryThenWhatPlaysTheLatestStartFirstThenWhatIsPausedTheLastToPlayFirst() {
        book.setApp("com.paused.old", state: Self.state("com.paused.old", playing: false), at: at(0))
        book.setApp("com.paused.new", state: Self.state("com.paused.new", playing: false), at: at(1))
        book.setApp("com.a", state: Self.state("com.a"), at: at(2))
        book.setApp("com.b", state: Self.state("com.b"), at: at(3))
        book.setApp("com.c", state: Self.state("com.c"), at: at(4))
        // The latest to start is the primary and first; then the others that play, the later start first.
        #expect(ids.map(\.rawValue) == ["app:com.c", "app:com.b", "app:com.a", "app:com.paused.new", "app:com.paused.old"])
        // A pin brings its source to the front, ahead of what started later.
        book.pin(.app("com.a"), at: at(5))
        #expect(ids.map(\.rawValue).first == "app:com.a")
        #expect(ids.map(\.rawValue).dropFirst().first == "app:com.c")
    }

    @Test mutating func aPausedSourceMovesBehindThosePlayingButTheChipsDoNotReshuffleForAPositionUpdate() {
        book.setApp("com.a", state: Self.state("com.a"), at: at(0))
        book.setApp("com.b", state: Self.state("com.b"), at: at(1))
        let before = ids
        var moved = Self.state("com.a")
        moved.elapsedAnchor = PlaybackAnchor(elapsedSeconds: 30, timestamp: at(2), rate: 1)
        book.setApp("com.a", state: moved, at: at(2))
        #expect(ids == before)
        book.setApp("com.b", state: Self.state("com.b", playing: false), at: at(3))
        #expect(ids.map(\.rawValue) == ["app:com.a", "app:com.b"])
    }

    // MARK: what the player shows

    @Test mutating func thePlayerFollowsThePrimaryUntilTheUserChoosesASource() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(1))
        #expect(book.displayedID == .app(Self.spotify))
        book.select(.app(Self.music), at: at(2))
        #expect(book.selectedID == .app(Self.music))
        #expect(book.displayedID == .app(Self.music))
        #expect(book.primaryID == .app(Self.spotify), "choosing what to look at does not change what the notch follows")
        // The primary changes hands, and the player stays where the user put it.
        book.setApp("com.new", state: Self.state("com.new"), at: at(3))
        #expect(book.displayedID == .app(Self.music))
    }

    @Test mutating func choosingThePrimaryGoesBackToFollowingIt() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(1))
        book.select(.app(Self.music), at: at(2))
        book.select(.app(Self.spotify), at: at(3))
        #expect(book.selectedID == nil)
        #expect(book.displayedID == .app(Self.spotify))
        book.select(.app(Self.music), at: at(4))
        // The primary becomes the source the user was looking at: nothing is left to "choose".
        book.setApp(Self.music, state: Self.state(Self.music, playing: false), at: at(5))
        book.setApp(Self.spotify, state: Self.state(Self.spotify, playing: false), at: at(6))
        book.pin(.app(Self.music), at: at(7))
        #expect(book.selectedID == nil)
        #expect(book.displayedID == .app(Self.music))
    }

    @Test mutating func aChosenSourceThatGoesAwayLeavesThePlayerOnThePrimaryOnceItHasBeenAwayForTheGrace() {
        book.setApp(Self.music, state: Self.state(Self.music), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(1))
        book.select(.app(Self.music), at: at(2))
        book.setApp(Self.music, state: nil, at: at(3))
        #expect(book.selectedID == .app(Self.music), "a blink is not a source going away")
        #expect(book.displayedID == .app(Self.music))
        book.expireTabs(at: at(3 + MediaSourceBook.releaseGrace))
        #expect(book.selectedID == nil)
        #expect(book.displayedID == .app(Self.spotify))
        book.select(.app(Self.music), at: at(10))
        #expect(book.selectedID == nil, "a source that is not there cannot be chosen")
    }

    @Test mutating func aChosenSourceThatComesBackInTimeIsStillChosen() {
        book.setApp(Self.music, state: Self.state(Self.music, "One"), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify), at: at(1))
        book.select(.app(Self.music), at: at(2))
        book.setApp(Self.music, state: nil, at: at(3))
        book.setApp(Self.music, state: Self.state(Self.music, "Two"), at: at(3.4))
        #expect(book.displayedID == .app(Self.music))
        #expect(book.displayed?.state.title == "Two")
        #expect(book.nextExpiry == nil)
    }

    // MARK: apps the user did not allow

    @Test mutating func anAppTheUserDidNotAllowIsHiddenFromWhatItReportsButNotFromTheSystem() {
        book.setApp(Self.music, state: Self.state(Self.music, playing: false), at: at(0))
        book.setApp(Self.spotify, state: Self.state(Self.spotify, playing: false), at: at(0))
        book.setHidden(Self.music, true, at: at(1))
        #expect(ids == [.app(Self.spotify)])
        // The system's own session for it is another thing: it is controlled through the system.
        book.setSystem(Self.state(Self.music, "Playing"), at: at(2))
        #expect(Set(ids) == [.app(Self.spotify), .app(Self.music)])
        #expect(book.entry(.app(Self.music))?.isSystemBacked == true)
        book.setSystem(nil, at: at(3))
        #expect(ids == [.app(Self.spotify)])
        book.setHidden(Self.music, false, at: at(4))
        #expect(Set(ids) == [.app(Self.spotify), .app(Self.music)])
        #expect(!book.isHidden(Self.music))
    }

    // MARK: tabs

    @Test mutating func aTabThatIsGoneAndAChromeThatIsGoneTakeTheirSourcesWithThem() {
        let a = TabRef(connection: 1, tab: 1)
        let b = TabRef(connection: 1, tab: 2)
        let c = TabRef(connection: 2, tab: 1)
        book.setTab(a, state: Self.tabState("A"), at: at(0))
        book.setTab(b, state: Self.tabState("B"), at: at(1))
        book.setTab(c, state: Self.tabState("C"), at: at(2))
        book.setTab(a, state: nil, at: at(3))
        #expect(Set(ids) == [.tab(b), .tab(c)])
        book.removeTabs(ofConnection: 1, at: at(4))
        #expect(ids == [.tab(c)])
        #expect(book.primaryID == .tab(c))
    }

    @Test mutating func aTabNotHeardFromForTheLiveWindowIsGoneAndOnlyThenAndTheNextExpiryIsTheOldestsOne() {
        let a = TabRef(connection: 1, tab: 1)
        let b = TabRef(connection: 1, tab: 2)
        #expect(book.nextExpiry == nil)
        book.setTab(a, state: Self.tabState("A"), at: at(0))
        book.setTab(b, state: Self.tabState("B"), at: at(100))
        #expect(book.nextExpiry == at(MediaSourceBook.tabLiveWindow))
        book.expireTabs(at: at(MediaSourceBook.tabLiveWindow - 1))
        #expect(ids.count == 2)
        book.expireTabs(at: at(MediaSourceBook.tabLiveWindow))
        #expect(ids == [.tab(b)])
        #expect(book.nextExpiry == at(100 + MediaSourceBook.tabLiveWindow))
        // A report is news: it moves the tab's expiry.
        book.setTab(b, state: Self.tabState("B"), at: at(200))
        #expect(book.nextExpiry == at(200 + MediaSourceBook.tabLiveWindow))
        book.expireTabs(at: at(200 + MediaSourceBook.tabLiveWindow))
        #expect(book.entries.isEmpty)
        #expect(book.nextExpiry == nil)
    }

    @Test mutating func aTabKeepsItsSiteAndAnEntryForItCanBeFoundByReference() {
        let ref = TabRef(connection: 3, tab: 9)
        book.setTab(ref, state: Self.tabState("Song"), site: "radio.example.org", at: at(0))
        #expect(book.entry(forTab: ref)?.site == "radio.example.org")
        #expect(book.entry(forTab: TabRef(connection: 3, tab: 10)) == nil)
        #expect(book.entry(.tab(ref))?.tab == ref)
    }
}
