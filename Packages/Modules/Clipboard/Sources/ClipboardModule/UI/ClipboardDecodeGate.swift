import Synchronization

/// Lets a few pictures be decoded at once and queues the rest in the order they asked. Every decode that runs at the same time
/// leaves its own working memory behind in the process (about 5 MB each for a large screenshot, measured), so how many run at once
/// is what sets the library's high-water mark when it opens on a screenful of screenshots.
///
/// A request whose task is cancelled while it waits leaves the queue and is told so; it never runs. The state sits behind a lock
/// because the cancellation handler runs on whatever thread cancels.
nonisolated final class ClipboardDecodeGate: Sendable {
    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct State {
        var running = 0
        var peak = 0
        var nextID: UInt64 = 0
        var waiters: [Waiter] = []
    }

    let limit: Int
    private let state = Mutex(State())

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// The slots in use, the most there have been at once, and the requests waiting for one.
    var running: Int { state.withLock { $0.running } }
    var peak: Int { state.withLock { $0.peak } }
    var queued: Int { state.withLock { $0.waiters.count } }

    /// True when the caller holds a slot, which it must give back with `release()`; false when its task was cancelled before it got one.
    func acquire() async -> Bool {
        let id = state.withLock { state -> UInt64 in
            state.nextID += 1
            return state.nextID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let answer: Bool? = state.withLock { state in
                    // Under the lock: a cancel that came first is seen here, and one that comes later finds this waiter in the queue.
                    if Task.isCancelled { return false }
                    if state.running < limit {
                        state.running += 1
                        state.peak = max(state.peak, state.running)
                        return true
                    }
                    state.waiters.append(Waiter(id: id, continuation: continuation))
                    return nil
                }
                if let answer { continuation.resume(returning: answer) }
            }
        } onCancel: {
            let waiter: Waiter? = state.withLock { state in
                state.waiters.firstIndex { $0.id == id }.map { state.waiters.remove(at: $0) }
            }
            waiter?.continuation.resume(returning: false)
        }
    }

    /// Gives a slot back: the oldest request waiting gets it, or it is free again.
    func release() {
        let next: Waiter? = state.withLock { state in
            guard !state.waiters.isEmpty else {
                state.running -= 1
                return nil
            }
            // Handed over, so the number running stays what it was.
            return state.waiters.removeFirst()
        }
        next?.continuation.resume(returning: true)
    }
}
