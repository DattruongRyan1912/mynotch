import Foundation
import MyNotchCore
import Testing
@testable import AIAgentsModule

/// The finished check is a notice (an activity with an expiry): it takes the notch from playing media for its few
/// seconds and gives it back, while working and waiting stay ongoing activities without one.
extension AIAgentsModuleTests {
    @Test func aFinishedCheckTakesTheNotchFromMediaForItsFewSecondsAndGivesItBack() async {
        await start()
        publishPlayingMedia()
        send(.turnStarted)
        await settle { harness.activities.others.count == 1 }
        #expect(current?.id == "media/nowPlaying")
        send(.turnFinished)
        await settle { current?.id == "aiagents/agent" }
        #expect(current?.id == "aiagents/agent")
        #expect(current?.activity.expiresAfter == .seconds(5) + AIAgentsModule.finishedExpiryMargin)
        #expect(harness.activities.others.map(\.id) == ["media/nowPlaying"])
        harness.scheduler.advance(by: .seconds(5))
        await settle { current?.id == "media/nowPlaying" }
        #expect(current?.id == "media/nowPlaying")
        #expect(harness.activities.others.isEmpty)
    }

    @Test func theFinishedChecksExpiryIsTheConfiguredDuration() async {
        harness.settings.set(12, for: keys.finishedSeconds)
        await start()
        send(.turnStarted)
        send(.turnFinished)
        await settle { module.publishedActivity?.kind == .finished }
        #expect(current?.activity.expiresAfter == .seconds(12) + AIAgentsModule.finishedExpiryMargin)
    }

    /// The module never claims an activity the center has already dropped: its own state follows the store's timer and
    /// leads the center's expiry, so the two agree at every step of the check's life and after it.
    @Test func theModulesStateNeverOutlivesTheCentersEntry() async {
        await start()
        send(.turnStarted)
        send(.turnFinished)
        await settle { module.publishedActivity?.kind == .finished }
        for _ in 0..<80 {
            harness.scheduler.advance(by: .milliseconds(100))
            #expect(module.publishedActivity == nil || current != nil)
            // Lets the observation loop follow the store, as the main loop would between two timers.
            for _ in 0..<50 { await Task.yield() }
        }
        #expect(module.publishedActivity == nil && current == nil)
    }

    @Test func workingAndWaitingAreNotNotices() async {
        await start()
        send(.turnStarted)
        await settle { current != nil }
        #expect(current?.activity.expiresAfter == nil)
        send(.waitingForInput)
        await settle { current?.activity.priority == .high }
        #expect(current?.activity.expiresAfter == nil)
    }
}
