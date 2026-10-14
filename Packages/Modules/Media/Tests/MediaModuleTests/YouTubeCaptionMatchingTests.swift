import Foundation
import Testing
import YouTubeBridgeKit
@testable import MediaModule

@Suite struct YouTubeCaptionMatchingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let videoID = YouTubeTestMessages.videoID

    func chrome(title: String? = YouTubeTestMessages.title) -> NowPlayingState {
        NowPlayingState(bundleIdentifier: "com.google.Chrome", title: title, artist: "Channel")
    }

    /// A store that has the captions and, `age` seconds before `now`, a playback.
    func store(
        title: String = YouTubeTestMessages.title, playing: Bool = true, age: TimeInterval = 1
    ) -> YouTubeCaptionStore {
        var store = YouTubeCaptionStore()
        store.apply(YouTubeTestMessages.captions(), at: now - 30)
        store.apply(YouTubeTestMessages.playback(title: title, playing: playing), at: now - age)
        return store
    }

    func match(_ state: NowPlayingState, _ store: YouTubeCaptionStore, keeping: String? = nil) -> YouTubeCaptionStore.Track? {
        YouTubeCaptionMatcher.track(for: state, in: store, now: now, keeping: keeping)
    }

    // MARK: title

    @Test func titlesAreComparedComposedCaseFoldedAndWithCollapsedWhitespace() {
        let normalised = YouTubeCaptionMatcher.normalised
        #expect(normalised("Em  Của\tNgày   Hôm Qua") == normalised("em của ngày hôm qua"))
        // Letters written as a base letter plus combining accents, against the single composed character.
        #expect(normalised("Tie\u{0302}ng") == normalised("Ti\u{00EA}ng"))
        #expect(normalised("Tie\u{0302}\u{0301}ng") == normalised("Ti\u{1EBF}ng"))
        #expect(normalised("  Sample\nvideo ") == "sample video")
        #expect(normalised("Straße") == normalised("STRASSE"))
        #expect(normalised("Sample video") != normalised("Sample videos"))
    }

    // MARK: the conditions

    @Test func aBrowserPlayingTheVideoWithAFreshPlaybackAndMatchingTitleGetsItsCaptions() {
        let track = match(chrome(), store())
        #expect(track?.lines == YouTubeTestMessages.lines)
        #expect(track?.videoID == videoID)
    }

    @Test func aBrowsersHelperProcessCountsThroughItsParent() {
        let state = NowPlayingState(
            bundleIdentifier: "com.google.Chrome.helper", parentApplicationBundleIdentifier: "com.google.Chrome", title: YouTubeTestMessages.title
        )
        #expect(match(state, store()) != nil)
        #expect(match(NowPlayingState(bundleIdentifier: "com.apple.Safari", title: YouTubeTestMessages.title), store()) != nil)
    }

    @Test func aPlayerThatIsNoBrowserNeverGetsThem() {
        for bundle in ["com.spotify.client", "com.apple.Music", "org.videolan.vlc"] {
            #expect(match(NowPlayingState(bundleIdentifier: bundle, title: YouTubeTestMessages.title), store()) == nil, "\(bundle)")
        }
    }

    @Test func aPlaybackOlderThanTenSecondsIsStale() {
        #expect(match(chrome(), store(age: 10)) != nil)
        #expect(match(chrome(), store(age: 10.5)) == nil)
        #expect(match(chrome(), store(age: 120)) == nil)
    }

    @Test func aPausedPlaybackDoesNotMatch() {
        #expect(match(chrome(), store(playing: false)) == nil)
    }

    @Test func theTitleMustMatchAfterNormalising() {
        #expect(match(chrome(title: "  SAMPLE   video "), store()) != nil)
        #expect(match(chrome(title: "Another video"), store()) == nil)
        #expect(match(chrome(title: nil), store()) == nil)
        #expect(match(chrome(), store(title: "Another video")) == nil)
    }

    @Test func withoutAPlaybackOrWithoutCaptionsForItsVideoThereIsNothing() {
        var onlyCaptions = YouTubeCaptionStore()
        onlyCaptions.apply(YouTubeTestMessages.captions(), at: now)
        #expect(match(chrome(), onlyCaptions) == nil)

        var otherVideo = YouTubeCaptionStore()
        otherVideo.apply(YouTubeTestMessages.captions("zzzzzzzzzzz"), at: now)
        otherVideo.apply(YouTubeTestMessages.playback(), at: now)
        #expect(match(chrome(), otherVideo) == nil)
    }

    // MARK: keeping a match

    @Test func aMatchOfTheSameVideoSurvivesAPauseAndASilentPage() {
        #expect(match(chrome(), store(playing: false), keeping: videoID) != nil)
        #expect(match(chrome(), store(age: 600), keeping: videoID) != nil)
    }

    @Test func aKeptMatchStillNeedsTheSameTitleVideoAndBrowser() {
        #expect(match(chrome(title: "Another video"), store(playing: false), keeping: videoID) == nil)
        #expect(match(chrome(), store(playing: false), keeping: "zzzzzzzzzzz") == nil)
        let spotify = NowPlayingState(bundleIdentifier: "com.spotify.client", title: YouTubeTestMessages.title)
        #expect(match(spotify, store(playing: false), keeping: videoID) == nil)
    }

    @Test func aKeptMatchEndsWithTheCaptionsThemselves() {
        var cleared = store(playing: false)
        cleared.apply(YouTubeTestMessages.clear(), at: now)
        #expect(match(chrome(), cleared, keeping: videoID) == nil)
    }

    // MARK: the decision and its reason

    func decision(_ state: NowPlayingState, _ store: YouTubeCaptionStore, keeping: String? = nil) -> YouTubeCaptionMatcher.Decision {
        YouTubeCaptionMatcher.decision(for: state, in: store, now: now, keeping: keeping)
    }

    /// nil unless matched.
    func isKept(_ decision: YouTubeCaptionMatcher.Decision) -> Bool? {
        if case .matched(_, let isKept) = decision { isKept } else { nil }
    }

    @Test func aMatchSaysWhetherItIsNewOrKept() {
        #expect(isKept(decision(chrome(), store())) == false)
        #expect(isKept(decision(chrome(), store(playing: false), keeping: videoID)) == true)
        #expect(isKept(decision(chrome(), store(playing: false))) == nil)
    }

    @Test func everyFailureNamesTheRuleThatFailed() {
        let spotify = NowPlayingState(bundleIdentifier: "com.spotify.client", title: YouTubeTestMessages.title)
        #expect(decision(spotify, store()) == .notMatched(.notBrowser))
        #expect(decision(chrome(title: "Another video"), store()) == .notMatched(.titleMismatch))
        #expect(decision(chrome(), store(playing: false)) == .notMatched(.paused))
        #expect(decision(chrome(), store(age: 30)) == .notMatched(.stalePlayback))
        // Paused and silent for long is a pause first.
        #expect(decision(chrome(), store(playing: false, age: 30)) == .notMatched(.paused))
    }

    @Test func whatHasNotArrivedYetIsNamedToo() {
        #expect(decision(chrome(title: nil), store()) == .notMatched(.noTitle))
        #expect(decision(chrome(), YouTubeCaptionStore()) == .notMatched(.noPlayback))
        var withoutCaptions = YouTubeCaptionStore()
        withoutCaptions.apply(YouTubeTestMessages.playback(), at: now)
        #expect(decision(chrome(), withoutCaptions) == .notMatched(.noCaptions))
    }

    @Test func theReasonsAreFixedWords() {
        typealias Reason = YouTubeCaptionMatcher.Reason
        let reasons: [Reason] = [.notBrowser, .noTitle, .noPlayback, .titleMismatch, .noCaptions, .paused, .stalePlayback]
        #expect(reasons.map(\.rawValue) == ["not-browser", "no-title", "no-playback", "title-mismatch", "no-captions", "paused", "stale-playback"])
    }

    @Test func theTrackOfADecisionIsNilUnlessMatched() {
        #expect(decision(chrome(), store()).track?.videoID == videoID)
        #expect(decision(chrome(), store(playing: false)).track == nil)
    }
}
