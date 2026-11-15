import Foundation

/// Runs blocking work, such as the helper's wait for an answer, on a thread of its own: not on one of the cooperative
/// pool's, which several tests waiting at once would use up, nor on a dispatch queue's, whose pool is slow to grow
/// when the machine is busy.
func runBlocking<T: Sendable>(_ work: @escaping @Sendable () -> T) -> Task<T, Never> {
    Task {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: work()) }
        }
    }
}
