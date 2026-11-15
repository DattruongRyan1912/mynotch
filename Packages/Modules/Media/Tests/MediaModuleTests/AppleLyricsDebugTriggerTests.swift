#if DEBUG
import Foundation
import Testing
@testable import MediaModule

/// The DEBUG-only trigger that runs an Apple lookup for a song id without playing anything. No real distributed
/// notification is posted or observed here: `receive(_:)` is what the observer calls, and the observer itself is a seam.
@Suite struct AppleLyricsDebugTriggerTests {
    let log = FakeAppleMusicLog()

    final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
    }

    final class Asked {
        var ids: [String] = []
        var result = LyricsResult.notFound
    }

    func makeTrigger(clock: Clock, asked: Asked) -> AppleLyricsDebugTrigger {
        AppleLyricsDebugTrigger(
            lookUp: { id in
                asked.ids.append(id)
                return asked.result
            },
            log: log, now: { clock.now }, observe: { _ in {} }
        )
    }

    @Test func aNumericIdIsLookedUp() async {
        let (clock, asked) = (Clock(), Asked())
        let trigger = makeTrigger(clock: clock, asked: asked)
        let task = trigger.receive("1856960468")
        await task?.value
        #expect(task != nil)
        #expect(asked.ids == ["1856960468"])
    }

    @Test(arguments: ["", " ", "abc", "12a", "a12", "12 3", "-5", "1.5", "1,5", "١٢٣", "12\n34", "0x12", "1856960468; rm", String(repeating: "1", count: 21)])
    func anythingButDigitsIsIgnoredWithoutUsingTheRateLimit(object: String) async {
        let (clock, asked) = (Clock(), Asked())
        let trigger = makeTrigger(clock: clock, asked: asked)
        #expect(trigger.receive(object) == nil)
        #expect(trigger.receive(nil) == nil)
        #expect(asked.ids.isEmpty)
        // An ignored id does not count against the limit.
        await trigger.receive("42")?.value
        #expect(asked.ids == ["42"])
        // Nothing the sender put in the object reaches the log.
        #expect(log.messages.allSatisfy { !$0.contains(object) || object.isEmpty || object == " " })
        #expect(log.messages.contains("Apple debug lookup: ignored, the object is not a numeric song id"))
    }

    @Test func oneLookupPerFiveSeconds() async {
        let (clock, asked) = (Clock(), Asked())
        let trigger = makeTrigger(clock: clock, asked: asked)
        await trigger.receive("1")?.value
        clock.now = clock.now.addingTimeInterval(4.9)
        #expect(trigger.receive("2") == nil)
        #expect(log.messages.contains("Apple debug lookup: ignored, one lookup per 5 seconds"))
        clock.now = clock.now.addingTimeInterval(0.1)
        await trigger.receive("3")?.value
        #expect(trigger.receive("4") == nil)
        clock.now = clock.now.addingTimeInterval(60)
        await trigger.receive("5")?.value
        #expect(asked.ids == ["1", "3", "5"])
        #expect(AppleLyricsDebugTrigger.minimumInterval == 5)
    }

    @Test func aClockThatWentBackDoesNotBlockForEver() async {
        let (clock, asked) = (Clock(), Asked())
        let trigger = makeTrigger(clock: clock, asked: asked)
        await trigger.receive("1")?.value
        clock.now = clock.now.addingTimeInterval(-3_600)
        await trigger.receive("2")?.value
        #expect(asked.ids == ["1", "2"])
    }

    @Test func theOutcomeIsLoggedAtNoticeLevelAsAKindAndALineCountOnly() async {
        let (clock, asked) = (Clock(), Asked())
        let trigger = makeTrigger(clock: clock, asked: asked)
        let cases: [(LyricsResult, String)] = [
            (.synced([LyricLine(time: 1, text: "secretlyric one"), LyricLine(time: 2, text: "secretlyric two"), LyricLine(time: 3, text: "")]), "Apple debug lookup: result=synced lines=3"),
            (.plain("secretlyric one\nsecretlyric two\n\nsecretlyric three"), "Apple debug lookup: result=plain lines=3"),
            (.notFound, "Apple debug lookup: result=notFound"),
            (.instrumental, "Apple debug lookup: result=instrumental"),
            (.unavailable("Apple Music did not return the lyrics it lists"), "Apple debug lookup: result=unavailable reason=Apple Music did not return the lyrics it lists"),
        ]
        for (result, line) in cases {
            asked.result = result
            clock.now = clock.now.addingTimeInterval(10)
            await trigger.receive("1856960468")?.value
            #expect(log.messages(at: .default).contains(line), "\(line)")
        }
        #expect(log.messages.allSatisfy { !$0.contains("secretlyric") })
        #expect(log.entries.allSatisfy { $0.level == .default })
    }

    @Test func startingObservesOnceAndStoppingRemovesTheObserver() {
        let (clock, asked) = (Clock(), Asked())
        var observers = 0
        var removed = 0
        let trigger = AppleLyricsDebugTrigger(lookUp: { _ in .notFound }, log: log, now: { clock.now }, observe: { _ in
            observers += 1
            return { removed += 1 }
        })
        _ = asked
        #expect(!trigger.isObserving)
        trigger.start()
        trigger.start()
        #expect(trigger.isObserving)
        #expect(observers == 1)
        trigger.stop()
        trigger.stop()
        #expect(!trigger.isObserving)
        #expect(removed == 1)
    }

    @Test func whatTheObserverDeliversIsHandledLikeAnyObject() async {
        let (clock, asked) = (Clock(), Asked())
        var deliver: (@MainActor (String?) -> Void)?
        let trigger = AppleLyricsDebugTrigger(
            lookUp: { id in asked.ids.append(id); return .notFound }, log: log, now: { clock.now },
            observe: { handler in deliver = handler; return {} }
        )
        trigger.start()
        deliver?("77")
        for _ in 0..<50 where asked.ids.isEmpty { await Task.yield() }
        #expect(asked.ids == ["77"])
        deliver?(nil)
        #expect(asked.ids == ["77"])
    }

    @Test func theNotificationHasTheDocumentedName() {
        #expect(AppleLyricsDebugTrigger.notificationName.rawValue == "io.lucasvu.mynotch.debug.appleLyrics")
    }
}
#endif
