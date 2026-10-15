import Foundation
import Testing
@testable import AIAgentsModule

/// Which subagents of one session run, which one finished last, and what happens to a stop that never came.
@Suite struct SubagentTrackerTests {
    let start = utc("2026-10-14T05:00:00Z")

    func at(_ seconds: TimeInterval) -> Date { start + seconds }

    @Test func aStartCountsAndItsStopUncountsIt() {
        var tracker = SubagentTracker()
        #expect(tracker.runningCount == 0)
        tracker.started(id: "a1", type: "Explore", at: at(0))
        tracker.started(id: "a2", type: "Plan", at: at(1))
        #expect(tracker.runningCount == 2)
        tracker.stopped(id: "a1", type: "Explore", at: at(5))
        #expect(tracker.runningCount == 1)
        tracker.stopped(id: "a2", type: "Plan", at: at(6))
        #expect(tracker.runningCount == 0)
    }

    @Test func aRepeatedStartOfTheSameIdIsStillOneSubagent() {
        var tracker = SubagentTracker()
        tracker.started(id: "a1", type: "Explore", at: at(0))
        tracker.started(id: "a1", type: "Explore", at: at(1))
        #expect(tracker.runningCount == 1)
    }

    @Test func theLastFinishedIsNamedByTheDescriptionOfItsCall() {
        var tracker = SubagentTracker()
        tracker.requested(type: "Explore", description: "Find API endpoints", at: at(0))
        tracker.started(id: "a1", type: "Explore", at: at(1))
        tracker.stopped(id: "a1", type: "Explore", at: at(9))
        #expect(tracker.lastFinished?.label == "Find API endpoints")
        #expect(tracker.lastFinished?.finishedAt == at(9))
    }

    @Test func withoutADescriptionItIsNamedByItsType() {
        var tracker = SubagentTracker()
        tracker.started(id: "a1", type: "Explore", at: at(0))
        tracker.stopped(id: "a1", type: "Explore", at: at(9))
        #expect(tracker.lastFinished?.label == "Explore")
    }

    @Test func aStopWithNothingToNameItLeavesTheLastFinishedAlone() {
        var tracker = SubagentTracker()
        tracker.started(id: "a1", type: "Explore", at: at(0))
        tracker.stopped(id: "a1", type: "Explore", at: at(1))
        tracker.started(id: "a2", type: nil, at: at(2))
        tracker.stopped(id: "a2", type: nil, at: at(3))
        #expect(tracker.lastFinished?.label == "Explore")
        #expect(tracker.runningCount == 0)
    }

    @Test func aStopOfASubagentItNeverSawStillRecordsWhatFinished() {
        var tracker = SubagentTracker()
        tracker.stopped(id: "late", type: "Plan", at: at(4))
        #expect(tracker.runningCount == 0)
        #expect(tracker.lastFinished?.label == "Plan")
    }

    @Test func aSecondStopOfTheSameSubagentKeepsTheDescription() {
        var tracker = SubagentTracker()
        tracker.requested(type: "Explore", description: "Find API endpoints", at: at(0))
        tracker.started(id: "a1", type: "Explore", at: at(1))
        tracker.stopped(id: "a1", type: "Explore", at: at(5))
        // Two helpers (the plugin and settings.json) both report every event.
        tracker.stopped(id: "a1", type: "Explore", at: at(5))
        #expect(tracker.lastFinished?.label == "Find API endpoints")
        #expect(tracker.lastFinished?.finishedAt == at(5))
        #expect(tracker.runningCount == 0)
    }

    @Test func aResumedSubagentThatFinishesAgainIsTheLastFinishedAgain() {
        var tracker = SubagentTracker()
        tracker.requested(type: "Explore", description: "First job", at: at(0))
        tracker.started(id: "a1", type: "Explore", at: at(1))
        tracker.stopped(id: "a1", type: "Explore", at: at(2))
        tracker.started(id: "a1", type: "Explore", at: at(10))
        #expect(tracker.runningCount == 1)
        tracker.stopped(id: "a1", type: "Explore", at: at(12))
        #expect(tracker.runningCount == 0)
        #expect(tracker.lastFinished?.finishedAt == at(12))
    }

    @Test func descriptionsGoToSubagentsOfTheirTypeInTheOrderTheyWereAsked() {
        var tracker = SubagentTracker()
        tracker.requested(type: "Explore", description: "First explore", at: at(0))
        tracker.requested(type: "Plan", description: "A plan", at: at(0))
        tracker.requested(type: "Explore", description: "Second explore", at: at(0))
        tracker.started(id: "p", type: "Plan", at: at(1))
        tracker.started(id: "e1", type: "Explore", at: at(1))
        tracker.started(id: "e2", type: "Explore", at: at(1))
        tracker.stopped(id: "e2", type: "Explore", at: at(2))
        #expect(tracker.lastFinished?.label == "Second explore")
        tracker.stopped(id: "e1", type: "Explore", at: at(3))
        #expect(tracker.lastFinished?.label == "First explore")
        tracker.stopped(id: "p", type: "Plan", at: at(4))
        #expect(tracker.lastFinished?.label == "A plan")
    }

    @Test func aCallWithoutATypeFitsAnyStartAndAStartWithoutATypeFitsAnyCall() {
        var tracker = SubagentTracker()
        tracker.requested(type: nil, description: "Anything", at: at(0))
        tracker.started(id: "a1", type: "general-purpose", at: at(1))
        tracker.requested(type: "Explore", description: "Look around", at: at(2))
        tracker.started(id: "a2", type: nil, at: at(3))
        tracker.stopped(id: "a1", type: "general-purpose", at: at(4))
        #expect(tracker.lastFinished?.label == "Anything")
        tracker.stopped(id: "a2", type: nil, at: at(5))
        #expect(tracker.lastFinished?.label == "Look around")
    }

    @Test func aSubagentOfAnotherTypeDoesNotTakeTheDescription() {
        var tracker = SubagentTracker()
        tracker.requested(type: "Explore", description: "Look around", at: at(0))
        tracker.started(id: "a1", type: "Plan", at: at(1))
        tracker.stopped(id: "a1", type: "Plan", at: at(2))
        #expect(tracker.lastFinished?.label == "Plan")
    }

    @Test func aDescriptionNobodyTookInTimeIsForgotten() {
        var tracker = SubagentTracker()
        tracker.requested(type: "Explore", description: "Old call", at: at(0))
        tracker.started(id: "a1", type: "Explore", at: at(SubagentTracker.callTimeout))
        tracker.stopped(id: "a1", type: "Explore", at: at(SubagentTracker.callTimeout + 1))
        #expect(tracker.lastFinished?.label == "Explore")
    }

    @Test func aDescriptionJustWithinTheTimeIsStillTaken() {
        var tracker = SubagentTracker()
        tracker.requested(type: "Explore", description: "Fresh call", at: at(0))
        tracker.started(id: "a1", type: "Explore", at: at(SubagentTracker.callTimeout - 0.001))
        tracker.stopped(id: "a1", type: "Explore", at: at(SubagentTracker.callTimeout))
        #expect(tracker.lastFinished?.label == "Fresh call")
    }

    // MARK: Stops that never come

    @Test func aSubagentSilentForTooLongIsDroppedAndTheOthersStay() {
        var tracker = SubagentTracker()
        tracker.started(id: "quiet", type: "Explore", at: at(0))
        tracker.started(id: "busy", type: "Plan", at: at(0))
        tracker.touch(id: "busy", at: at(SubagentTracker.silenceTimeout - 1))
        #expect(!tracker.hasExpired(at: at(SubagentTracker.silenceTimeout - 0.001)))
        #expect(tracker.hasExpired(at: at(SubagentTracker.silenceTimeout)))
        tracker.expire(at: at(SubagentTracker.silenceTimeout))
        #expect(tracker.runningCount == 1)
        #expect(!tracker.hasExpired(at: at(SubagentTracker.silenceTimeout)))
        tracker.expire(at: at(2 * SubagentTracker.silenceTimeout))
        #expect(tracker.runningCount == 0)
    }

    @Test func aDroppedSubagentIsNotMadeTheLastFinished() {
        var tracker = SubagentTracker()
        tracker.started(id: "gone", type: "Explore", at: at(0))
        tracker.expire(at: at(SubagentTracker.silenceTimeout))
        #expect(tracker.lastFinished == nil)
    }

    @Test func theSilenceTimeoutIsLongEnoughForAToolButNotForAnHour() {
        #expect(SubagentTracker.silenceTimeout >= 5 * 60)
        #expect(SubagentTracker.silenceTimeout <= 30 * 60)
        #expect(SubagentTracker.callTimeout >= 5 && SubagentTracker.callTimeout <= 120)
    }

    @Test func touchingAnUnknownSubagentOrWithAnOldTimeChangesNothing() {
        var tracker = SubagentTracker()
        tracker.touch(id: "nobody", at: at(10))
        #expect(tracker.runningCount == 0)
        tracker.started(id: "a1", type: nil, at: at(100))
        tracker.touch(id: "a1", at: at(50))
        #expect(tracker.hasExpired(at: at(100 + SubagentTracker.silenceTimeout)))
    }

    @Test func expiringOldDescriptionsIsAChangeToo() {
        var tracker = SubagentTracker()
        tracker.requested(type: nil, description: "Never taken", at: at(0))
        #expect(!tracker.hasExpired(at: at(1)))
        #expect(tracker.hasExpired(at: at(SubagentTracker.callTimeout)))
        tracker.expire(at: at(SubagentTracker.callTimeout))
        #expect(!tracker.hasExpired(at: at(SubagentTracker.callTimeout)))
    }

    @Test func resetEndsTheRunningOnesButKeepsWhatFinished() {
        var tracker = SubagentTracker()
        tracker.started(id: "a1", type: "Explore", at: at(0))
        tracker.stopped(id: "a1", type: "Explore", at: at(1))
        tracker.started(id: "a2", type: "Plan", at: at(2))
        tracker.requested(type: "Plan", description: "pending", at: at(2))
        tracker.reset()
        #expect(tracker.runningCount == 0)
        #expect(tracker.lastFinished?.label == "Explore")
        tracker.started(id: "a3", type: "Plan", at: at(3))
        tracker.stopped(id: "a3", type: "Plan", at: at(4))
        #expect(tracker.lastFinished?.label == "Plan")
    }

    // MARK: Bounds

    @Test func noMoreThanTheLimitRunAndTheOldestGoFirst() {
        var tracker = SubagentTracker()
        for index in 0..<(SubagentTracker.maxRunning + 5) { tracker.started(id: "a\(index)", type: nil, at: at(TimeInterval(index))) }
        #expect(tracker.runningCount == SubagentTracker.maxRunning)
        tracker.stopped(id: "a0", type: "Explore", at: at(1_000))
        #expect(tracker.runningCount == SubagentTracker.maxRunning)
        tracker.stopped(id: "a\(SubagentTracker.maxRunning + 4)", type: nil, at: at(1_001))
        #expect(tracker.runningCount == SubagentTracker.maxRunning - 1)
    }

    @Test func noMoreThanTheLimitOfCallsWait() {
        var tracker = SubagentTracker()
        for index in 0..<(SubagentTracker.maxCalls + 5) { tracker.requested(type: nil, description: "call \(index)", at: at(0)) }
        for index in 0..<SubagentTracker.maxCalls { tracker.started(id: "a\(index)", type: nil, at: at(1)) }
        tracker.stopped(id: "a0", type: nil, at: at(2))
        // The oldest five were pushed out, so the first start got the sixth call.
        #expect(tracker.lastFinished?.label == "call 5")
    }
}
