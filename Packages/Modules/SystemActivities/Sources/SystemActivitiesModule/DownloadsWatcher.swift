import CoreServices
import Foundation
import MyNotchCore

/// Source of finished downloads; faked in tests.
protocol DownloadsWatching: AnyObject {
    /// Calls `onDownload` for each download that finishes, until `stop()`. Returns false when watching is impossible,
    /// which includes a folder the user has not allowed access to, and when the calling task was cancelled meanwhile.
    /// It suspends while macOS asks for access to the folder, so cancel the task before starting again.
    @discardableResult
    func start(_ onDownload: @escaping (DownloadEvent) -> Void) async -> Bool
    func stop()
}

/// Watches a folder (`~/Downloads` by default) with file-level FSEvents and reports finished downloads.
/// Files already in the folder when it starts are not reported.
final class DownloadsWatcher: DownloadsWatching {
    private let directory: URL
    private let scheduler: any Scheduler
    private let now: () -> Date
    private let probe: @Sendable (String) -> Bool
    private var rule = DownloadCompletionRule()
    private var stream: FSEventStreamRef?
    private var onDownload: ((DownloadEvent) -> Void)?
    private var nextTick: ScheduledAction?

    /// `probe` is told the folder's path and says whether it can be read; tests replace it.
    init(
        directory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
        scheduler: any Scheduler, now: @escaping () -> Date = Date.init,
        probe: @escaping @Sendable (String) -> Bool = DownloadsWatcher.canRead(atPath:)
    ) {
        self.directory = directory.standardizedFileURL
        self.scheduler = scheduler
        self.now = now
        self.probe = probe
    }

    var isWatching: Bool { stream != nil }

    isolated deinit { stop() }

    /// Reads the folder once first: FSEvents alone neither makes macOS ask for access to a protected folder such as
    /// Downloads nor reports that it was refused, while listing it asks on first use and fails when denied. That read
    /// blocks until the user answers the prompt, so it runs off the main thread and the stream is created afterwards.
    /// Returns false when the folder cannot be read, the event stream cannot be created, or the task was cancelled.
    @discardableResult
    func start(_ onDownload: @escaping (DownloadEvent) -> Void) async -> Bool {
        stop()
        let (path, probe) = (directory.path, probe)
        guard !Task.isCancelled, await Task.detached(operation: { probe(path) }).value, !Task.isCancelled else { return false }
        self.onDownload = onDownload
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<DownloadsWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let flags = Array(UnsafeBufferPointer(start: flags, count: count))
            MainActor.assumeIsolated { watcher.receive(zip(paths, flags).map { ($0, $1) }) }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [directory.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return false }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    private nonisolated static func canRead(atPath path: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    func stop() {
        nextTick?.cancel()
        nextTick = nil
        onDownload = nil
        rule = DownloadCompletionRule()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Ignores a callback that was already queued when `stop()` ran.
    func receive(_ events: [(path: String, flags: FSEventStreamEventFlags)]) {
        guard onDownload != nil else { return }
        let time = now()
        for event in events {
            let url = URL(fileURLWithPath: event.path)
            // Only direct children: the contents of a `.download` bundle are not downloads.
            guard url.deletingLastPathComponent().standardizedFileURL == directory else { continue }
            rule.observe(FileObservation.read(url, flags: Self.flags(event.flags)), now: time)
        }
        scheduleTick()
    }

    private func tick() {
        nextTick = nil
        let events = rule.tick(now: now())
        scheduleTick()
        events.forEach { onDownload?($0) }
    }

    private func scheduleTick() {
        guard nextTick == nil, rule.hasPending else { return }
        nextTick = scheduler.schedule(after: .milliseconds(300)) { [weak self] in self?.tick() }
    }

    private static func flags(_ raw: FSEventStreamEventFlags) -> FileObservation.Flags {
        var flags: FileObservation.Flags = []
        if raw & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 { flags.insert(.created) }
        if raw & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 { flags.insert(.renamed) }
        if raw & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 { flags.insert(.removed) }
        let modified = kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemXattrMod
        if raw & FSEventStreamEventFlags(modified) != 0 { flags.insert(.modified) }
        return flags
    }
}
