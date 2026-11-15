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
    done: Date? = nil,
    repeats: Bool = false
) -> TodoReminder {
    TodoReminder(
        id: id, title: id, due: due, priority: priority, isCompleted: done != nil, completionDate: done,
        listID: list, listTitle: list.capitalized, listColor: .gray, isRecurring: repeats
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
