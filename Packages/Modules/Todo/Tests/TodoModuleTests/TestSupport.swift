import Foundation
import Synchronization
@testable import TodoModule

/// A Gregorian calendar pinned to one time zone, so day boundaries don't depend on the machine running the tests.
nonisolated func fixedCalendar(_ timeZone: String = "Asia/Ho_Chi_Minh") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    return calendar
}

extension Calendar {
    /// October `day`, 2026 at `hour:minute:second` in this calendar's time zone.
    func on(_ day: Int, at hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }
}

/// A due date as Reminders stores it: a day alone, or a day with a time. October 2026.
func due(_ day: Int, _ hour: Int? = nil, _ minute: Int = 0) -> DateComponents {
    DateComponents(
        calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: day, hour: hour, minute: hour == nil ? nil : minute
    )
}

/// An incomplete reminder in the "inbox" list unless told otherwise; `done` makes it completed at that moment.
func todo(
    _ id: String,
    due: DateComponents? = nil,
    priority: TodoPriority = .none,
    list: String = "inbox",
    done: Date? = nil
) -> TodoReminder {
    TodoReminder(
        id: id, title: id, due: due, priority: priority, isCompleted: done != nil, completionDate: done,
        listID: list, listTitle: list.capitalized, listColor: .gray
    )
}

/// The module's "now": tests move it, then trigger a refresh.
final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// Lets tasks the module started finish: work that hops to the data source takes a few turns of the main actor.
func settle(timeout: Duration = .seconds(5), until condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(2))
    }
}

/// A short wait for the "nothing happens" checks, so a late task would have shown up.
func letAnythingPending() async {
    try? await Task.sleep(for: .milliseconds(60))
}

nonisolated final class Counter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }

    func increment() {
        count.withLock { $0 += 1 }
    }
}

/// A clock that only moves when a test says so, so nothing depends on how accurately the machine sleeps.
nonisolated final class ManualClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var sleepCalls = 0
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// How many times something has started waiting on this clock, cancelled waits included. A test that fed a
    /// change waits for this to grow, which tells it the change has been taken and its wait is in place.
    var sleepCalls: Int { state.withLock { $0.sleepCalls } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { state -> Int in
            state.sleepCalls += 1
            return state.sleepCalls
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let outcome: Result<Void, any Error>? = state.withLock { state in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if deadline <= state.now { return .success(()) }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return nil
                }
                if let outcome { continuation.resume(with: outcome) }
            }
        } onCancel: {
            let sleeper = state.withLock { state in
                state.sleepers.firstIndex { $0.id == id }.map { state.sleepers.remove(at: $0) }
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes everything whose deadline has come.
    func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.deadline <= state.now }
            state.sleepers.removeAll { $0.deadline <= state.now }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}

/// Holds whoever calls `wait()` until the test calls `open()`.
nonisolated final class AsyncGate: Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
        var waitCalls = 0
    }

    private let state = Mutex(State())

    /// How many callers have arrived, so a test can wait until one is held.
    var waitCalls: Int { state.withLock { $0.waitCalls } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let passes = state.withLock { state -> Bool in
                state.waitCalls += 1
                if !state.isOpen { state.waiters.append(continuation) }
                return state.isOpen
            }
            if passes { continuation.resume() }
        }
    }

    func open() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }
}
