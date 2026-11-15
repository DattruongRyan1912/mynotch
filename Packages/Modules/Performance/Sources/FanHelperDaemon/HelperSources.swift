import Dispatch
import Foundation

/// The helper's dispatch sources, made here and not in `main.swift` on purpose. The tool target defaults to the main actor, so a
/// handler closure written in `main.swift` is main-actor isolated, and the runtime traps when a source runs it on the controller
/// queue instead of the main one. This target has no main-actor default and the handlers are `@Sendable`, so they cannot be.
public enum HelperSources {
    /// Calls `handler` on `queue` every `interval` seconds, the first time one interval from now. Already running; keep the
    /// source alive for as long as it should keep running.
    public static func timer(
        on queue: DispatchQueue, every interval: TimeInterval, _ handler: @escaping @Sendable () -> Void
    ) -> any DispatchSourceTimer {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler(handler: handler)
        source.resume()
        return source
    }

    /// Calls `handler` on `queue` when the process receives `signalNumber`, whose default action (ending the process) is turned
    /// off, so that `handler` decides. Already running; keep the source alive for as long as it should keep running.
    public static func signal(
        _ signalNumber: Int32, on queue: DispatchQueue, _ handler: @escaping @Sendable () -> Void
    ) -> any DispatchSourceSignal {
        Foundation.signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
        source.setEventHandler(handler: handler)
        source.resume()
        return source
    }
}
