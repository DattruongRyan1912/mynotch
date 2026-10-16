import Foundation

/// Lets the helper go when nobody is connected: a root process that stays around for no reason is a thing to avoid, and launchd
/// starts it again when the app next connects. Counts the open connections; when there are none for `delay` seconds, calls `onExit`
/// once.
public final class IdleExit: @unchecked Sendable {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let onExit: @Sendable () -> Void
    private var open = 0
    private var pending: DispatchWorkItem?
    private var exited = false

    public init(after delay: TimeInterval, queue: DispatchQueue = DispatchQueue(label: "io.lucasvu.mynotch.fanhelper.idle"), onExit: @escaping @Sendable () -> Void) {
        self.delay = delay
        self.queue = queue
        self.onExit = onExit
    }

    /// Starts the clock for a helper that nobody has connected to yet.
    public func start() {
        queue.async { self.armIfIdle() }
    }

    public func connectionOpened() {
        queue.async {
            self.open += 1
            self.pending?.cancel()
            self.pending = nil
        }
    }

    public func connectionClosed() {
        queue.async {
            self.open = max(0, self.open - 1)
            self.armIfIdle()
        }
    }

    private func armIfIdle() {
        guard open == 0, !exited else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [self] in
            guard open == 0, !exited else { return }
            exited = true
            onExit()
        }
        pending = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
