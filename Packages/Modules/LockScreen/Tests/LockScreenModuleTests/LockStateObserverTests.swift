import AppKit
import Foundation
import Testing
@testable import LockScreenModule

/// Returns once everything already queued on the main queue has run. The observer hops there, so a notification
/// posted just before has been handled by then, and one it ignored is known to have changed nothing.
func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        OperationQueue.main.addOperation { continuation.resume() }
    }
}

/// Private stand-ins for the distributed and workspace notification centers: nothing reaches the system.
@MainActor
final class NotificationFixture {
    let distributed = NotificationCenter()
    let workspace = NotificationCenter()
    private(set) var changes: [LockStateObserver.State] = []
    let observer: LockStateObserver

    init(initiallyLocked: Bool = false) {
        observer = LockStateObserver(distributed: distributed, workspace: workspace, isScreenLocked: { initiallyLocked })
        observer.start { [unowned self] in changes.append($0) }
    }

    func post(_ name: Notification.Name, on center: NotificationCenter) async {
        center.post(name: name, object: nil)
        await drainMainQueue()
    }

    func lock() async { await post(LockStateObserver.screenIsLocked, on: distributed) }
    func unlock() async { await post(LockStateObserver.screenIsUnlocked, on: distributed) }
    func sleepDisplay() async { await post(NSWorkspace.screensDidSleepNotification, on: workspace) }
    func wakeDisplay() async { await post(NSWorkspace.screensDidWakeNotification, on: workspace) }
    func resignSession() async { await post(NSWorkspace.sessionDidResignActiveNotification, on: workspace) }
    func activateSession() async { await post(NSWorkspace.sessionDidBecomeActiveNotification, on: workspace) }
}

@Suite struct LockStateObserverTests {
    @Test func startsFromTheSessionsLockedState() {
        #expect(NotificationFixture(initiallyLocked: true).observer.state.isLocked)
        #expect(!NotificationFixture(initiallyLocked: false).observer.state.isLocked)
    }

    @Test func aLockedSessionIsVisibleAtOnce() {
        #expect(NotificationFixture(initiallyLocked: true).observer.state.isLockScreenVisible)
        #expect(!NotificationFixture(initiallyLocked: false).observer.state.isLockScreenVisible)
    }

    @Test func lockAndUnlockNotificationsFlipTheState() async {
        let fixture = NotificationFixture()
        await fixture.lock()
        #expect(fixture.observer.state.isLockScreenVisible)
        await fixture.unlock()
        #expect(!fixture.observer.state.isLocked)
        #expect(fixture.changes.map(\.isLockScreenVisible) == [true, false])
    }

    @Test func theDisplaySleepingHidesTheLockScreenAndWakingBringsItBack() async {
        let fixture = NotificationFixture(initiallyLocked: true)
        await fixture.sleepDisplay()
        #expect(fixture.observer.state.isLocked)
        #expect(!fixture.observer.state.isLockScreenVisible)
        await fixture.wakeDisplay()
        #expect(fixture.observer.state.isLockScreenVisible)
    }

    @Test func lockingWhileTheDisplayIsAsleepWaitsForItToWake() async {
        let fixture = NotificationFixture()
        await fixture.sleepDisplay()
        await fixture.lock()
        #expect(!fixture.observer.state.isLockScreenVisible)
        await fixture.wakeDisplay()
        #expect(fixture.observer.state.isLockScreenVisible)
    }

    @Test func leavingTheSessionHidesTheLockScreenUntilItIsBack() async {
        let fixture = NotificationFixture(initiallyLocked: true)
        await fixture.resignSession()
        #expect(!fixture.observer.state.isLockScreenVisible)
        await fixture.activateSession()
        #expect(fixture.observer.state.isLockScreenVisible)
    }

    @Test func unlockingForgetsASleepWhoseWakeWasMissed() async {
        let fixture = NotificationFixture(initiallyLocked: true)
        await fixture.sleepDisplay()
        await fixture.unlock()
        #expect(!fixture.observer.state.isDisplayAsleep)
        await fixture.lock()
        #expect(fixture.observer.state.isLockScreenVisible)
    }

    @Test func aRepeatedNotificationIsNotAChange() async {
        let fixture = NotificationFixture()
        await fixture.lock()
        await fixture.post(LockStateObserver.screenIsLocked, on: fixture.distributed)
        await fixture.post(NSWorkspace.screensDidWakeNotification, on: fixture.workspace)
        #expect(fixture.changes.count == 1)
    }

    @Test func eachNotificationIsOnlyHeardOnItsOwnCenter() async {
        let fixture = NotificationFixture()
        await fixture.post(LockStateObserver.screenIsLocked, on: fixture.workspace)
        await fixture.post(NSWorkspace.screensDidSleepNotification, on: fixture.distributed)
        #expect(fixture.changes.isEmpty)
    }

    @Test func stoppingEndsTheObservation() async {
        let fixture = NotificationFixture()
        fixture.observer.stop()
        await fixture.post(LockStateObserver.screenIsLocked, on: fixture.distributed)
        #expect(fixture.changes.isEmpty)
        #expect(!fixture.observer.state.isLocked)
    }

    @Test func startingAgainReadsTheSessionAgain() {
        var locked = false
        let observer = LockStateObserver(distributed: NotificationCenter(), workspace: NotificationCenter(), isScreenLocked: { locked })
        observer.start { _ in }
        #expect(!observer.state.isLocked)
        locked = true
        observer.start { _ in }
        #expect(observer.state.isLocked)
    }

    @Test func stateMachineEvents() {
        var state = LockStateObserver.State(isLocked: false)
        state.apply(.locked)
        state.apply(.displaySlept)
        state.apply(.sessionResigned)
        #expect(state == .init(isLocked: true, isDisplayAsleep: true, isSessionActive: false))
        state.apply(.unlocked)
        #expect(state == .init(isLocked: false, isDisplayAsleep: false, isSessionActive: false))
        state.apply(.sessionBecameActive)
        #expect(state == .init(isLocked: false))
    }

    @Test func sessionDictionaryParsing() {
        #expect(!LockStateObserver.isScreenLocked(in: nil))
        #expect(!LockStateObserver.isScreenLocked(in: [:]))
        #expect(!LockStateObserver.isScreenLocked(in: ["CGSSessionScreenIsLocked": false]))
        #expect(LockStateObserver.isScreenLocked(in: ["CGSSessionScreenIsLocked": true]))
        #expect(LockStateObserver.isScreenLocked(in: ["CGSSessionScreenIsLocked": 1]))
        #expect(!LockStateObserver.isScreenLocked(in: ["CGSSessionScreenIsLocked": "yes"]))
    }
}
