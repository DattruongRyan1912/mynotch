import Dispatch

/// Waits until the main queue has run what was queued before this call, such as output and exit callbacks that were
/// already on their way. It is not a pause: it cannot tell that nothing is still to come from another thread.
func drainMainQueue() async {
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
}
