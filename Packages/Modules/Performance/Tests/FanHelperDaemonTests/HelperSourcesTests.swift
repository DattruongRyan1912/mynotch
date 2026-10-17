import Dispatch
import Foundation
import Synchronization
import Testing
@testable import FanHelperDaemon

/// The helper runs on `io.lucasvu.mynotch.fanhelper.controller`, never on the main queue: a handler that is main-actor isolated traps
/// there. The sources are built in this target, which has no main-actor default, and take `@Sendable` handlers, so the tool's
/// `main.swift` (whose target does default to the main actor) cannot give them one that is.
@Suite struct HelperSourcesTests {
    private func makeQueue(_ key: DispatchSpecificKey<Void>) -> DispatchQueue {
        let queue = DispatchQueue(label: "MyNotchTests.fanhelper.controller")
        queue.setSpecific(key: key, value: ())
        return queue
    }

    @Test func aTimerCallsItsHandlerOnItsQueueAgainAndAgain() {
        let key = DispatchSpecificKey<Void>()
        let queue = makeQueue(key)
        let places = Mutex<[(onQueue: Bool, onMain: Bool)]>([])
        let tick = DispatchSemaphore(value: 0)
        let timer = HelperSources.timer(on: queue, every: 0.01) {
            places.withLock { $0.append((DispatchQueue.getSpecific(key: key) != nil, Thread.isMainThread)) }
            tick.signal()
        }
        for _ in 0..<3 { #expect(tick.wait(timeout: .now() + 5) == .success) }
        timer.cancel()
        let seen = places.withLock { $0 }
        #expect(seen.count >= 3)
        #expect(seen.allSatisfy { $0.onQueue && !$0.onMain })
    }

    @Test func aTimerStopsWhenItIsCancelled() {
        let queue = makeQueue(DispatchSpecificKey<Void>())
        let calls = Mutex(0)
        let first = DispatchSemaphore(value: 0)
        let timer = HelperSources.timer(on: queue, every: 0.01) {
            calls.withLock { $0 += 1 }
            first.signal()
        }
        #expect(first.wait(timeout: .now() + 5) == .success)
        timer.cancel()
        queue.sync {}
        let atCancel = calls.withLock { $0 }
        Thread.sleep(forTimeInterval: 0.05)
        #expect(calls.withLock { $0 } == atCancel)
    }

    /// SIGWINCH is ignored by default, so the process cannot be hurt if the handler were missing; it is the one the system
    /// itself sends for a resized terminal.
    @Test func aSignalCallsItsHandlerOnItsQueueAndTheProcessGoesOn() {
        let key = DispatchSpecificKey<Void>()
        let queue = makeQueue(key)
        let place = Mutex<(onQueue: Bool, onMain: Bool)?>(nil)
        let received = DispatchSemaphore(value: 0)
        let source = HelperSources.signal(SIGWINCH, on: queue) {
            place.withLock { $0 = (DispatchQueue.getSpecific(key: key) != nil, Thread.isMainThread) }
            received.signal()
        }
        raise(SIGWINCH)
        #expect(received.wait(timeout: .now() + 5) == .success)
        source.cancel()
        let seen = place.withLock { $0 }
        #expect(seen?.onQueue == true)
        #expect(seen?.onMain == false)
    }
}
