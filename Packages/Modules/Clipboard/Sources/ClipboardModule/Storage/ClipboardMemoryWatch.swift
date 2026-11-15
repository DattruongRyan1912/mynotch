import Dispatch

/// Memory pressure from the system, as a value of two closures so a test fires it without causing any: pressure is the whole
/// machine's, never something a test may make.
struct ClipboardMemoryPressure {
    enum Level: Sendable {
        case warning
        case critical
    }

    /// Starts listening and returns what `stop` needs. `handler` runs on the main actor.
    var start: (@escaping @MainActor @Sendable (Level) -> Void) -> Any
    var stop: (Any) -> Void

    /// `DispatchSource`'s memory pressure source, for the warning and the critical level, on the main queue.
    static let system = ClipboardMemoryPressure(
        start: { handler in
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
            source.setEventHandler { [weak source] in
                guard let source else { return }
                let level: Level = source.data.contains(.critical) ? .critical : .warning
                MainActor.assumeIsolated { handler(level) }
            }
            source.activate()
            return source
        },
        stop: { ($0 as? any DispatchSourceMemoryPressure)?.cancel() }
    )
}

/// Owns the module's listener for memory pressure while the module runs: started with it and cancelled when it stops. A holder of its
/// own so the module's class needs one line for it; tests replace `pressure` with a fake before the module starts.
final class ClipboardMemoryWatch {
    var pressure = ClipboardMemoryPressure.system
    private var token: Any?

    var isWatching: Bool { token != nil }

    /// Listens until `stop`. Starting again first stops the one that was listening.
    func start(_ handler: @escaping @MainActor @Sendable (ClipboardMemoryPressure.Level) -> Void) {
        stop()
        token = pressure.start(handler)
    }

    func stop() {
        guard let token else { return }
        self.token = nil
        pressure.stop(token)
    }
}
