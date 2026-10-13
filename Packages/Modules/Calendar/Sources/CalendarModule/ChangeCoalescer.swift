import Foundation

/// Turns bursts of change notifications into one signal each.
nonisolated enum ChangeCoalescer {
    /// Signals once `quietPeriod` has passed without another change, so the many notifications of a sync or a
    /// bulk edit cost one refresh. A source that ends still delivers the signal it was waiting to send.
    static func coalescing(_ source: AsyncStream<Void>, quietPeriod: Duration) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                var pending: Task<Void, Never>?
                for await _ in source {
                    pending?.cancel()
                    pending = Task {
                        guard (try? await Task.sleep(for: quietPeriod)) != nil else { return }
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
