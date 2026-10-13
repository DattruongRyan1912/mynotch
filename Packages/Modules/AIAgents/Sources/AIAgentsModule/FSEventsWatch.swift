import CoreServices
import Foundation

/// An FSEvents stream over directories, with file-level events so that appending to a transcript is reported.
/// Only says that something changed: the paths are not needed, the watcher rescans.
nonisolated final class FSEventsWatch: AgentWatchHandle, @unchecked Sendable {
    /// Keeps the callback alive for as long as the stream may call it.
    private final class Callback {
        let onChange: @Sendable () -> Void
        init(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    }

    /// Events are delivered at most this often; the first one after a quiet time arrives at once (`NoDefer`).
    private static let latency: CFTimeInterval = 0.05

    private let queue = DispatchQueue(label: "io.lucasvu.mynotch.aiagents.fsevents", qos: .utility)
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    /// With no stream (the system refused), the watch does nothing; the heartbeat still rescans.
    init(paths: [String], onChange: @escaping @Sendable () -> Void) {
        guard !paths.isEmpty else { return }
        let callback = Callback(onChange)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { info in info.map { _ = Unmanaged<Callback>.fromOpaque($0).retain() }; return info },
            release: { info in info.map { Unmanaged<Callback>.fromOpaque($0).release() } },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue().onChange()
            },
            &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    deinit {
        cancel()
    }

    func cancel() {
        let stream = lock.withLock {
            defer { self.stream = nil }
            return self.stream
        }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
