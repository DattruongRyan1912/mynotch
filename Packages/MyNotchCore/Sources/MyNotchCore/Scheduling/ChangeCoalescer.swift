import Foundation

/// Turns bursts of change notifications into one signal each.
public nonisolated enum ChangeCoalescer {
    /// Signals once `quietPeriod` has passed without another change, so the many notifications of a sync or a
    /// bulk edit cost one refresh. A burst that never goes quiet still signals `maxWait` after its first change,
    /// so a store that keeps changing is not left stale. A source that ends still delivers the signal it was
    /// waiting to send. Nothing runs for a stream that is dropped without being iterated: the source is released.
    public static func coalescing(_ source: AsyncStream<Void>, quietPeriod: Duration, maxWait: Duration = .seconds(5)) -> AsyncStream<Void> {
        coalescing(source, quietPeriod: quietPeriod, maxWait: maxWait, clock: ContinuousClock())
    }

    /// The same, timed by `clock`, so a test moves time by hand instead of depending on how long a sleep takes.
    public static func coalescing<C: Clock>(
        _ source: AsyncStream<Void>, quietPeriod: Duration, maxWait: Duration = .seconds(5), clock: C
    ) -> AsyncStream<Void> where C.Duration == Duration, C.Instant: Sendable {
        AsyncStream { continuation in
            let task = Task {
                var pending: Task<Void, Never>?
                var burst: (start: C.Instant, last: C.Instant)?
                for await _ in source {
                    let now = clock.now
                    pending?.cancel()
                    // A burst that went quiet or reached the max wait has signaled already; this change starts the next one.
                    var start = now
                    if let current = burst, current.last.duration(to: now) < quietPeriod, now < current.start.advanced(by: maxWait) {
                        start = current.start
                    }
                    burst = (start, now)
                    let deadline = min(now.advanced(by: quietPeriod), start.advanced(by: maxWait))
                    pending = Task {
                        guard (try? await clock.sleep(until: deadline, tolerance: nil)) != nil else { return }
                        continuation.yield()
                    }
                }
                if Task.isCancelled { pending?.cancel() } else { await pending?.value }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
