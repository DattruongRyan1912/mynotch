import Dispatch

/// `HardwareQueue` over one serial dispatch queue. Results come back through the main queue, which keeps them in the
/// order the work was given.
final class SerialHardwareQueue: HardwareQueue {
    private let queue = DispatchQueue(label: "MyNotch.MediaKeys.hardware", qos: .userInitiated)

    init() {}

    func run<T: Sendable>(_ work: @escaping @Sendable () -> T, then completion: @escaping @MainActor (T) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(result) } }
        }
    }
}
