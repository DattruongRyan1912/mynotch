import AppKit
import Foundation
import MyNotchTestSupport
import Observation
import Testing
@testable import NotchUI

/// When memory is given back, with a manual clock and a fake in place of `malloc_zone_pressure_relief`: nothing here touches the
/// real heap.
@Suite struct MemoryReliefTests {
    /// What the fake gives back and where it ran.
    nonisolated final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var onMain: [Bool] = []
        private var reported: [Int] = []

        func relieve() -> Int {
            lock.withLock { onMain.append(Thread.isMainThread) }
            return 4_096
        }

        func report(_ bytes: Int) { lock.withLock { reported.append(bytes) } }

        var count: Int { lock.withLock { onMain.count } }
        var ranOnMain: [Bool] { lock.withLock { onMain } }
        var bytes: [Int] { lock.withLock { reported } }
    }

    let scheduler = ManualScheduler()
    let calls = Calls()
    let center = NotificationCenter()

    /// The relief runs where it is asked, so a test needs no wait; `theRealRunnerLeavesTheMainThread` uses the queue.
    func makeRelief() -> MemoryRelief {
        let calls = calls
        return MemoryRelief(
            scheduler: scheduler, relieve: { calls.relieve() }, report: { calls.report($0) },
            perform: { $0() }, notifications: center
        )
    }

    func seconds(_ value: Int) -> Duration { .seconds(value) }

    // MARK: - The notch

    @Test func aCollapsedNotchGivesMemoryBackAfterFiveSecondsNotBefore() {
        let relief = makeRelief()
        relief.notchChanged(isExpanded: true)
        relief.notchChanged(isExpanded: false)
        scheduler.advance(by: .milliseconds(4_900))
        #expect(calls.count == 0)
        scheduler.advance(by: .milliseconds(100))
        #expect(calls.count == 1)
        #expect(calls.bytes == [4_096])
        #expect(MemoryRelief.collapseDelay == .seconds(5))
    }

    @Test func aNotchThatOpensAgainBeforeTheWaitIsOverCancelsIt() {
        let relief = makeRelief()
        relief.notchChanged(isExpanded: true)
        relief.notchChanged(isExpanded: false)
        scheduler.advance(by: seconds(3))
        relief.notchChanged(isExpanded: true)
        #expect(!relief.isPending)
        scheduler.advance(by: seconds(60))
        #expect(calls.count == 0, "nothing runs while the notch is open")
    }

    @Test func collapsingAgainStartsTheWaitOver() {
        let relief = makeRelief()
        relief.notchChanged(isExpanded: true)
        relief.notchChanged(isExpanded: false)
        scheduler.advance(by: seconds(3))
        relief.notchChanged(isExpanded: true)
        scheduler.advance(by: seconds(1))
        relief.notchChanged(isExpanded: false)
        scheduler.advance(by: seconds(4))
        #expect(calls.count == 0)
        scheduler.advance(by: seconds(1))
        #expect(calls.count == 1)
    }

    @Test func aNotchThatWasNeverOpenGivesNothingBack() {
        let relief = makeRelief()
        relief.notchChanged(isExpanded: false)
        scheduler.advance(by: seconds(60))
        #expect(calls.count == 0)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func oneReliefPerQuietPeriodHoweverOftenTheNotchFlickers() {
        let relief = makeRelief()
        for _ in 0..<20 {
            relief.notchChanged(isExpanded: true)
            scheduler.advance(by: .milliseconds(200))
            relief.notchChanged(isExpanded: false)
            scheduler.advance(by: .milliseconds(300))
        }
        #expect(calls.count == 0)
        scheduler.advance(by: seconds(5))
        #expect(calls.count == 1)
        #expect(scheduler.pendingCount == 0)
    }

    // MARK: - Windows

    @Test func aWindowThatGoesAwayGivesMemoryBackAfterTwoSecondsAndASecondOneRestartsTheWait() {
        let relief = makeRelief()
        relief.windowWentAway()
        scheduler.advance(by: .milliseconds(1_500))
        relief.windowWentAway()
        scheduler.advance(by: .milliseconds(1_900))
        #expect(calls.count == 0)
        scheduler.advance(by: .milliseconds(100))
        #expect(calls.count == 1)
        #expect(MemoryRelief.windowDelay == .seconds(2))
    }

    @Test func aWindowThatGoesAwayWhileTheNotchIsOpenWaitsForTheNotchToCollapse() {
        let relief = makeRelief()
        relief.notchChanged(isExpanded: true)
        relief.windowWentAway()
        #expect(!relief.isPending)
        scheduler.advance(by: seconds(60))
        #expect(calls.count == 0)
        relief.notchChanged(isExpanded: false)
        scheduler.advance(by: seconds(5))
        #expect(calls.count == 1)
    }

    @Test func aWindowAfterTheCollapseReplacesItsWaitWithTheShorterOne() {
        let relief = makeRelief()
        relief.notchChanged(isExpanded: true)
        relief.notchChanged(isExpanded: false)
        scheduler.advance(by: seconds(1))
        relief.windowWentAway()
        scheduler.advance(by: seconds(2))
        #expect(calls.count == 1, "the later, shorter wait ran first")
        scheduler.advance(by: seconds(60))
        #expect(calls.count == 1)
    }

    // MARK: - Where it runs

    @Test func theRealRunnerLeavesTheMainThread() async {
        let calls = calls
        let ran = AsyncStream<Void>.makeStream()
        let relief = MemoryRelief(
            scheduler: scheduler, relieve: { calls.relieve() }, report: { calls.report($0); ran.continuation.yield() },
            perform: MemoryRelief.onUtilityQueue, notifications: center
        )
        relief.windowWentAway()
        scheduler.advance(by: seconds(2))
        var iterator = ran.stream.makeAsyncIterator()
        await iterator.next()
        #expect(calls.ranOnMain == [false])
        #expect(calls.bytes == [4_096])
    }

    @Test func theSystemReliefIsACountOfBytes() {
        // The real call, once: it may return any number of bytes, never a negative one.
        #expect(MemoryRelief.systemRelief() >= 0)
    }

    // MARK: - The app's windows

    func window() -> NSWindow {
        NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 30), styleMask: .titled, backing: .buffered, defer: true)
    }

    @Test func aWindowClosingIsHeard() {
        let relief = makeRelief()
        relief.start { false }
        center.post(name: NSWindow.willCloseNotification, object: window())
        #expect(relief.isPending)
        relief.stop()
    }

    @Test func aWindowOrderedOutIsHeardButOneThatIsStillThereIsNot() {
        let relief = makeRelief()
        relief.start { false }
        // Never ordered in, so it is not visible: like a panel that was ordered out.
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: window())
        #expect(relief.isPending)
        relief.stop()
        #expect(!relief.isPending)
    }

    @Test func theNotchsOwnPanelsAreNeverAReason() {
        let relief = makeRelief()
        relief.start { false }
        let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 40, height: 30), notifications: center)
        center.post(name: NSWindow.willCloseNotification, object: panel)
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        #expect(!relief.isPending)
        relief.stop()
    }

    @Test func startingTwiceListensOnce() {
        let relief = makeRelief()
        relief.start { false }
        relief.start { false }
        center.post(name: NSWindow.willCloseNotification, object: window())
        scheduler.advance(by: seconds(2))
        #expect(calls.count == 1)
        relief.stop()
    }

    @Test func stoppingStopsListeningAndCancelsTheWait() {
        let relief = makeRelief()
        relief.start { false }
        center.post(name: NSWindow.willCloseNotification, object: window())
        relief.stop()
        scheduler.advance(by: seconds(60))
        #expect(calls.count == 0)
        center.post(name: NSWindow.willCloseNotification, object: window())
        #expect(!relief.isPending)
    }

    // MARK: - Following the notches

    @Observable final class Notches {
        var isExpanded = false
    }

    @Test func theNotchesAreFollowedThroughAnObservation() async {
        let notches = Notches()
        let relief = makeRelief()
        relief.start { notches.isExpanded }
        func settle(until condition: () -> Bool) async {
            for _ in 0..<200 where !condition() { await Task.yield() }
        }
        notches.isExpanded = true
        await settle { false }
        notches.isExpanded = false
        await settle { relief.isPending }
        #expect(relief.isPending)
        scheduler.advance(by: seconds(5))
        #expect(calls.count == 1)
        relief.stop()
    }
}
