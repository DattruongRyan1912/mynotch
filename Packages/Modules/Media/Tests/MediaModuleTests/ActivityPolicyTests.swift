import Foundation
import Testing
@testable import MediaModule

@Suite struct ActivityPolicyTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func track(_ title: String = "Song", playing: Bool = true, bundle: String = "com.example.Player", parent: String? = nil) -> NowPlayingState {
        NowPlayingState(bundleIdentifier: bundle, parentApplicationBundleIdentifier: parent, title: title, isPlaying: playing)
    }

    @Test func pauseKeepsVisibleUntilGraceElapses() {
        var policy = ActivityPolicy()
        #expect(!policy.visible)
        policy.update(track(), at: start)
        #expect(policy.visible)
        #expect(policy.nextDeadline == nil)

        policy.update(track(playing: false), at: start + 10)
        #expect(policy.visible)
        #expect(policy.nextDeadline == start + 15)

        policy.update(track(playing: false), at: start + 12)
        #expect(policy.nextDeadline == start + 15)
        policy.tick(at: start + 14.9)
        #expect(policy.visible)
        policy.tick(at: start + 15)
        #expect(!policy.visible)
        #expect(policy.nextDeadline == nil)
    }

    @Test func resumingWithinGraceStaysVisible() {
        var policy = ActivityPolicy(pauseGrace: 3)
        policy.update(track(), at: start)
        policy.update(track(playing: false), at: start + 1)
        #expect(policy.nextDeadline == start + 4)
        policy.update(track(), at: start + 2)
        #expect(policy.visible)
        #expect(policy.nextDeadline == nil)
        policy.tick(at: start + 10)
        #expect(policy.visible)
    }

    @Test func pausedTrackNeverShowsAndZeroGraceHidesAtOnce() {
        var policy = ActivityPolicy(pauseGrace: 0)
        policy.update(track(playing: false), at: start)
        #expect(!policy.visible)
        policy.update(track(), at: start + 1)
        policy.update(track(playing: false), at: start + 2)
        #expect(!policy.visible)
    }

    @Test func emptyStateHidesOnlyAfterDebounce() {
        var policy = ActivityPolicy()
        policy.update(track(), at: start)
        policy.update(.empty, at: start + 1)
        #expect(policy.visible)
        #expect(policy.nextDeadline == start + 1.3)

        policy.update(NowPlayingState(bundleIdentifier: "com.example.Player"), at: start + 1.2)
        #expect(policy.nextDeadline == start + 1.3)
        policy.tick(at: start + 1.29)
        #expect(policy.visible)
        policy.tick(at: start + 1.3)
        #expect(!policy.visible)
        #expect(policy.nextDeadline == nil)
    }

    @Test func newTrackWithinDebounceCancelsTheHide() {
        var policy = ActivityPolicy()
        policy.update(track("First"), at: start)
        policy.update(track("First", playing: false), at: start + 1)
        policy.update(.empty, at: start + 1.05)
        policy.update(track("Second"), at: start + 1.2)
        #expect(policy.visible)
        #expect(policy.nextDeadline == nil)
        policy.tick(at: start + 10)
        #expect(policy.visible)
    }

    @Test func hiddenAppsAreNeverVisible() {
        var policy = ActivityPolicy(hiddenBundleIDs: ["com.example.Hidden"])
        policy.update(track(bundle: "com.example.Hidden"), at: start)
        #expect(!policy.visible)
        policy.update(track(bundle: "com.example.Hidden.helper", parent: "com.example.Hidden"), at: start + 1)
        #expect(!policy.visible)

        policy.update(track(), at: start + 2)
        #expect(policy.visible)
        policy.update(track(bundle: "com.example.Hidden"), at: start + 3)
        #expect(!policy.visible)
        #expect(policy.nextDeadline == nil)
    }
}
