import Foundation

/// Turns bursts of change notifications into one signal each.
nonisolated enum ChangeCoalescer {
    /// Signals once `quietPeriod` has passed without another change, so the many notifications of a sync or a
    /// bulk edit cost one refresh. A burst that never goes quiet still signals `maxWait` after its first change,
    /// so a calendar that keeps changing is not left stale. A source that ends still delivers the signal it was
    /// waiting to send. Nothing runs for a stream that is dropped without being iterated: the source is released.
    static func coalescing(_ source: AsyncStream<Void>, quietPeriod: Duration, maxWait: Duration = .seconds(5)) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                let clock = ContinuousClock()
                var pending: Task<Void, Never>?
                var burst: (start: ContinuousClock.Instant, last: ContinuousClock.Instant)?
                for await _ in source {
                    let now = clock.now
                    pending?.cancel()
                    // A burst that went quiet or reached the max wait has signaled already; this change starts the next one.
                    var start = now
                    if let current = burst, now - current.last < quietPeriod, now < current.start + maxWait {
                        start = current.start
                    }
                    burst = (start, now)
                    let deadline = min(now + quietPeriod, start + maxWait)
                    pending = Task {
                        guard (try? await clock.sleep(until: deadline)) != nil else { return }
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
