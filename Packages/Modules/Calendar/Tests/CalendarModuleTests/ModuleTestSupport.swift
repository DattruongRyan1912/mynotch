import Foundation
import Synchronization
@testable import CalendarModule

/// The module's "now": tests move it, then trigger a refresh.
final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// Stands in for NSWorkspace: records what the module opens, so no test launches an app or a browser.
final class RecordingOpener {
    private(set) var urls: [URL] = []
    /// URL schemes this opener cannot handle, like `ical` without Calendar.app.
    var unsupportedSchemes: Set<String> = []

    func open(_ url: URL) -> Bool {
        urls.append(url)
        return !unsupportedSchemes.contains(url.scheme ?? "")
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

func reminder(
    _ id: String,
    due: DateComponents? = nil,
    overdue: Bool = false,
    list: String = "Reminders"
) -> AgendaReminder {
    AgendaReminder(id: id, title: id, due: due, isOverdue: overdue, listTitle: list, listColor: .gray)
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
