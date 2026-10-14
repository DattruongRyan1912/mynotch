import Foundation
import Testing
import YouTubeBridgeKit
@testable import MediaModule

/// Where Next and Previous go for what plays now: MediaRemote, the Chrome extension, or nowhere.
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
        #expect(route(state("com.google.Chrome", title: "Sample videos"), store()) == .unavailable)
        #expect(route(state("com.google.Chrome", title: "Another video"), store()) == .unavailable)
    }

    @Test func aBrowsersHelperProcessCountsThroughItsParent() {
        let helper = state("com.google.Chrome.helper", parent: "com.google.Chrome")
        #expect(route(helper, store()) == .bridge)
        #expect(route(helper, YouTubeCaptionStore()) == .unavailable)
    }

    @Test func anotherBrowserWithALiveMatchedSessionIsStillServedByTheBridge() {
        #expect(route(state("com.apple.Safari"), store()) == .bridge)
    }

    // MARK: no live session

    @Test func chromeWithoutAnythingFromTheExtensionHasNoRoute() {
        #expect(route(state("com.google.Chrome"), YouTubeCaptionStore()) == .unavailable)
        #expect(route(state("com.google.Chrome", title: nil), store()) == .unavailable)
    }

    @Test func theSessionIsLiveWhilethePageWasHeardFromWithinTheWindow() {
        #expect(SkipRoute.liveWindow == 75, "a paused tab in the background tells it is there about once a minute")
        #expect(route(state("com.google.Chrome"), store(playbackAge: SkipRoute.liveWindow)) == .bridge)
        #expect(route(state("com.google.Chrome"), store(playbackAge: SkipRoute.liveWindow + 0.1)) == .unavailable)
    }

    @Test func aHeartbeatOfTheContentScriptKeepsAPausedVideosSessionAlive() {
        var heard = store(playbackAge: 600)
        #expect(route(state("com.google.Chrome"), heard) == .unavailable)
        heard.apply(YouTubeTestMessages.diag("content-alive videoid-present=true playing=false", from: .content), at: now - 20)
        #expect(route(state("com.google.Chrome"), heard) == .bridge)
    }

    @Test func theServiceWorkersOwnDiagnosticsDoNotKeepASessionAlive() {
        var heard = store(playbackAge: 600)
        heard.apply(YouTubeTestMessages.diag("sw-access youtube=granted"), at: now - 1)
        heard.apply(YouTubeTestMessages.diag("sw-start v=0.1.3"), at: now - 1)
        #expect(route(state("com.google.Chrome"), heard) == .unavailable)
    }

    // MARK: what MediaRemote can still do

    @Test func aPlayerThatIsNoBrowserAlwaysUsesMediaRemote() {
        for bundle in ["com.spotify.client", "com.apple.Music", "org.videolan.vlc"] {
            #expect(route(state(bundle), store()) == .mediaRemote, "\(bundle)")
            #expect(route(state(bundle), YouTubeCaptionStore()) == .mediaRemote, "\(bundle)")
        }
        #expect(route(NowPlayingState.empty, YouTubeCaptionStore()) == .mediaRemote)
    }

    @Test func aBrowserTheExtensionCannotServeKeepsMediaRemote() {
        // The extension is for Chrome: for these there is nothing to tell the user to install.
        for bundle in ["com.apple.Safari", "org.mozilla.firefox", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser"] {
            #expect(route(state(bundle), YouTubeCaptionStore()) == .mediaRemote, "\(bundle)")
            #expect(route(state(bundle, title: "Another video"), store()) == .mediaRemote, "\(bundle)")
        }
    }

    @Test func chromeIsRecognisedByItsBundleOrItsHelpersParent() {
        #expect(state("com.google.Chrome").isFromChrome)
        #expect(state("com.google.Chrome.helper", parent: "com.google.Chrome").isFromChrome)
        #expect(state("org.example.Helper", parent: "com.google.Chrome").isFromChrome)
        #expect(!state("com.apple.Safari").isFromChrome)
        #expect(!state("com.example.Player").isFromChrome)
        #expect(!NowPlayingState.empty.isFromChrome)
    }
}
