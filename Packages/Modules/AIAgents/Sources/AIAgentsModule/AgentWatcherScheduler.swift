import Foundation

/// The watcher's private queue and the timers that run on it: the debounce after a file event and the heartbeat.
/// Behind a protocol so tests can run both by hand, on the same queue, instead of waiting for the wall clock.
nonisolated protocol AgentWatcherScheduler: Sendable {
    /// Where everything the watcher owns runs.
    var queue: DispatchQueue { get }

    /// Runs `action` on `queue` once, after `delay`.
    func after(_ delay: DispatchTimeInterval, _ action: @escaping @Sendable () -> Void)

    /// Runs `action` on `queue` every `interval`, the first time after one interval, until the handle is cancelled.
    func every(_ interval: DispatchTimeInterval, _ action: @escaping @Sendable () -> Void) -> any AgentWatchHandle
}

/// The real clock: a utility queue with dispatch timers.
nonisolated struct QueueAgentWatcherScheduler: AgentWatcherScheduler {
    private nonisolated final class TimerHandle: AgentWatchHandle, @unchecked Sendable {
        private let timer: any DispatchSourceTimer
        init(_ timer: any DispatchSourceTimer) { self.timer = timer }
        func cancel() { timer.cancel() }
    }

    let queue = DispatchQueue(label: "io.lucasvu.mynotch.aiagents.watcher", qos: .utility)

    func after(_ delay: DispatchTimeInterval, _ action: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + delay, execute: action)
    }

    func every(_ interval: DispatchTimeInterval, _ action: @escaping @Sendable () -> Void) -> any AgentWatchHandle {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(1))
        timer.setEventHandler(handler: action)
        timer.resume()
        return TimerHandle(timer)
    }
}
