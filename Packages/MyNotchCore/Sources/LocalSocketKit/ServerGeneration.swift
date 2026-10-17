import Synchronization

/// A counter shared with the closures that run on a server's private queues. Work those queues hand to the main thread cannot
/// be recalled when the server stops; `stop` advances this instead, and the work that finds another value is dropped.
public final class ServerGeneration: Sendable {
    private let value = Mutex(0)

    public init() {}

    public var current: Int { value.withLock { $0 } }

    public func advance() { value.withLock { $0 += 1 } }
}
