import Foundation
import Testing
import YouTubeBridgeKit
@testable import MediaModule

/// Where Next and Previous go for what plays now: the Chrome extension when it has a live matched session, MediaRemote otherwise.
@Suite struct YouTubeSkipRouteTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let title = YouTubeTestMessages.title

    func state(_ bundle: String, parent: String? = nil, title: String? = YouTubeTestMessages.title) -> NowPlayingState {
        NowPlayingState(bundleIdentifier: bundle, parentApplicationBundleIdentifier: parent, title: title, artist: "Channel")
    }

    /// A store whose latest playback arrived `playbackAge` seconds before `now`.
    func store(title: String = YouTubeTestMessages.title, playing: Bool = true, playbackAge: TimeInterval = 1) -> YouTubeCaptionStore {
        var store = YouTubeCaptionStore()
        store.apply(YouTubeTestMessages.playback(title: title, playing: playing), at: now - playbackAge)
        return store
    }

    func route(_ state: NowPlayingState, _ store: YouTubeCaptionStore) -> SkipRoute {
        SkipRoute.decide(for: state, in: store, now: now)
    }

    // MARK: the bridge

    @Test func aChromeTabWhosePlaybackTheExtensionReportedGoesThroughTheBridgeWithNoCaptionsNeeded() {
        #expect(route(state("com.google.Chrome"), store()) == .bridge)
    }

    @Test func aPausedVideoStillGoesThroughTheBridge() {
        #expect(route(state("com.google.Chrome"), store(playing: false)) == .bridge)
    }

    @Test func theTitleIsComparedTheWayTheCaptionsAre() {
        #expect(route(state("com.google.Chrome", title: "  SAMPLE   video "), store()) == .bridge)
        #expect(route(state("com.google.Chrome", title: "Sample videos"), store()) == .mediaRemote)
        #expect(route(state("com.google.Chrome", title: "Another video"), store()) == .mediaRemote)
    }

    @Test func aBrowsersHelperProcessCountsThroughItsParent() {
        let helper = state("com.google.Chrome.helper", parent: "com.google.Chrome")
        #expect(route(helper, store()) == .bridge)
        #expect(route(helper, YouTubeCaptionStore()) == .mediaRemote)
    }

    @Test func anotherBrowserWithALiveMatchedSessionIsStillServedByTheBridge() {
        #expect(route(state("com.apple.Safari"), store()) == .bridge)
    }

    // MARK: no live session

    @Test func chromeWithoutAnythingFromTheExtensionKeepsMediaRemoteBecauseTheAppCannotTellWhichSitePlays() {
        // Spotify Web and YouTube Music skip through MediaRemote; only a live YouTube session needs the extension.
        #expect(route(state("com.google.Chrome"), YouTubeCaptionStore()) == .mediaRemote)
        #expect(route(state("com.google.Chrome", title: nil), store()) == .mediaRemote)
    }

    @Test func theSessionIsLiveWhilethePageWasHeardFromWithinTheWindow() {
        #expect(SkipRoute.liveWindow == 75, "a paused tab in the background tells it is there about once a minute")
        #expect(route(state("com.google.Chrome"), store(playbackAge: SkipRoute.liveWindow)) == .bridge)
        #expect(route(state("com.google.Chrome"), store(playbackAge: SkipRoute.liveWindow + 0.1)) == .mediaRemote)
    }

    @Test func aHeartbeatOfTheContentScriptKeepsAPausedVideosSessionAlive() {
        var heard = store(playbackAge: 600)
        #expect(route(state("com.google.Chrome"), heard) == .mediaRemote)
        heard.apply(YouTubeTestMessages.diag("content-alive videoid-present=true playing=false", from: .content), at: now - 20)
        #expect(route(state("com.google.Chrome"), heard) == .bridge)
    }

    @Test func theServiceWorkersOwnDiagnosticsDoNotKeepASessionAlive() {
        var heard = store(playbackAge: 600)
        heard.apply(YouTubeTestMessages.diag("sw-access youtube=granted"), at: now - 1)
        heard.apply(YouTubeTestMessages.diag("sw-start v=0.1.3"), at: now - 1)
        #expect(route(state("com.google.Chrome"), heard) == .mediaRemote)
    }

    // MARK: what MediaRemote can still do

    @Test func aPlayerThatIsNoBrowserAlwaysUsesMediaRemote() {
        for bundle in ["com.spotify.client", "com.apple.Music", "org.videolan.vlc"] {
            #expect(route(state(bundle), store()) == .mediaRemote, "\(bundle)")
            #expect(route(state(bundle), YouTubeCaptionStore()) == .mediaRemote, "\(bundle)")
        }
        #expect(route(NowPlayingState.empty, YouTubeCaptionStore()) == .mediaRemote)
    }

    @Test func aBrowserWithoutALiveMatchedSessionKeepsMediaRemote() {
        for bundle in ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser"] {
            #expect(route(state(bundle), YouTubeCaptionStore()) == .mediaRemote, "\(bundle)")
            #expect(route(state(bundle, title: "Another video"), store()) == .mediaRemote, "\(bundle)")
        }
    }
}
