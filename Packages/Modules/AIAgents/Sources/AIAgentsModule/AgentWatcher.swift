import Foundation
import Synchronization

/// Follows Claude Code's and Codex's files and feeds what they say to the store. FSEvents (through
/// `AgentFileSystem`) says when something changed; a debounced rescan then reads what was appended to each
/// transcript. Everything but the final `store.apply` runs on one private queue, off the main thread.
nonisolated final class AgentWatcher: @unchecked Sendable {
    /// A transcript found while running is read from here to its end, so the current turn's state is rebuilt
    /// without replaying a history of tens of megabytes.
    static let tailBytes: UInt64 = 64 * 1024
    /// A read takes at most this much, so a large append is parsed in pieces.
    private static let chunkBytes = 256 * 1024
    /// A Codex rollout's first line (`session_meta`) holds the whole instructions text; longer ones are skipped.
    private static let headerBytes = 256 * 1024
    /// Only files written to within this long are followed.
    private static let recentSeconds: TimeInterval = 24 * 3600

    private nonisolated struct Target {
        var source: AgentSource
        var sessionID: String
    }

    /// What `stat` says about a file, enough to tell that nothing was appended since the last read.
    private nonisolated struct FileStamp: Equatable {
        var device: dev_t
        var inode: ino_t
        var size: off_t
        var seconds: Int
        var nanoseconds: Int

        init?(of url: URL) {
            var info = stat()
            guard stat(url.path, &info) == 0 else { return nil }
            device = info.st_dev
            inode = info.st_ino
            size = info.st_size
            seconds = info.st_mtimespec.tv_sec
            nanoseconds = info.st_mtimespec.tv_nsec
        }
    }

    private nonisolated final class TrackedFile {
        let target: Target
        let url: URL
        let tailer: any LineTailing
        /// The file as it was before the last complete read. While it is unchanged there is nothing to read, so the
        /// scan neither opens nor reads it. Taken before reading: a write during the read shows as a change next time.
        var readStamp: FileStamp?
        var codexParser: CodexRolloutParser?
        /// A Codex rollout joined mid-way: its first line, which names the working directory and branch.
        var header: String?
        /// A Codex rollout read from its first line: its first running total is all of the session's usage.
        var awaitingFirstTotal: Bool

        init(target: Target, url: URL, tailer: any LineTailing, header: String?, awaitingFirstTotal: Bool) {
            self.target = target
            self.url = url
            self.tailer = tailer
            self.header = header
            self.awaitingFirstTotal = awaitingFirstTotal
            codexParser = target.source == .codex ? CodexRolloutParser(sessionID: target.sessionID) : nil
        }
    }

    private let store: AgentSessionStore
    private let claudeRoot: URL?
    private let codexRoot: URL?
    private let fileSystem: any AgentFileSystem
    private let makeTailer: @Sendable (_ url: URL, _ startOffset: UInt64) -> any LineTailing
    private let now: @Sendable () -> Date
    private let debounce: DispatchTimeInterval
    private let heartbeat: DispatchTimeInterval
    private let scheduler: any AgentWatcherScheduler
    private let queue: DispatchQueue
    /// Whether the watcher is wanted, and which start or stop call made it so. Set at once by `start` and `stop`
    /// and read on the main queue too, so a batch the queue already handed over is dropped when a stop came
    /// after it, even if the watcher has been started again since.
    private let run = Mutex(Run())

    private nonisolated struct Run {
        var isRunning = false
        var generation = 0
    }

    // Everything below belongs to `queue`.
    private var watch: (any AgentWatchHandle)?
    private var heartbeatTimer: (any AgentWatchHandle)?
    private var rescanScheduled = false
    private var watchesClaude = false
    private var watchesCodex = false
    private var tracked: [URL: TrackedFile] = [:]
    private var transcriptPaths: [String: URL] = [:]
    /// Sessions whose transcript was looked for and not found, so scans do not list every project folder again
    /// and again for them. Cleared when something may have created it (see `noteChanges`) and by the heartbeat.
    private var missingTranscripts: Set<String> = []
    private var lastRegistry: [ClaudeSessionInfo]?
    /// The last entry read from each registry file, by file name.
    private var registryEntries: [String: ClaudeSessionInfo] = [:]

    /// - Parameters:
    ///   - claudeRoot: `~/.claude`, or nil to leave Claude Code out.
    ///   - codexRoot: `~/.codex`, or nil to leave Codex out.
    ///   - debounce: how long after a file event the rescan waits, so a burst of writes costs one scan.
    ///   - heartbeat: how often to rescan without an event. A process that dies leaves its registry file behind
    ///     and touches no file, so only polling notices.
    ///   - scheduler: the queue the watcher runs on and the timers for the debounce and the heartbeat.
    init(
        store: AgentSessionStore,
        claudeRoot: URL?,
        codexRoot: URL?,
        fileSystem: any AgentFileSystem = LocalAgentFileSystem(),
        makeTailer: @escaping @Sendable (URL, UInt64) -> any LineTailing = { JSONLTailer(url: $0, startOffset: $1) },
        now: @escaping @Sendable () -> Date = { Date() },
        debounce: DispatchTimeInterval = .milliseconds(100),
        heartbeat: DispatchTimeInterval = .seconds(10),
        scheduler: any AgentWatcherScheduler = QueueAgentWatcherScheduler()
    ) {
        self.store = store
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
        self.fileSystem = fileSystem
        self.makeTailer = makeTailer
        self.now = now
        self.debounce = debounce
        self.heartbeat = heartbeat
        self.scheduler = scheduler
        queue = scheduler.queue
    }

    /// Starts watching the roots that exist now; a missing one (Codex not installed) stays off until the next start.
    func start() {
        let ticket = run.withLock { run -> Int? in
            guard !run.isRunning else { return nil }
            run.isRunning = true
            run.generation += 1
            return run.generation
        }
        guard let ticket else { return }
        queue.async { [self] in
            // A stop that came after this start leaves the watcher stopped.
            guard run.withLock({ $0.isRunning && $0.generation == ticket }) else { return }
            beginWatching()
            scan()
        }
    }

    /// Stops reading and forgets every file offset. Nothing reaches the store after this returns: a batch a
    /// scan already handed to the main queue is dropped when it arrives. The watch itself is cancelled on the
    /// watcher's queue, so this never waits for a scan that is still reading.
    func stop() {
        run.withLock { run in
            run.isRunning = false
            run.generation += 1
        }
        queue.async { [self] in
            watch?.cancel()
            watch = nil
            heartbeatTimer?.cancel()
            heartbeatTimer = nil
            rescanScheduled = false
            watchesClaude = false
            watchesCodex = false
            tracked = [:]
            transcriptPaths = [:]
            missingTranscripts = []
            lastRegistry = nil
            registryEntries = [:]
        }
    }

    /// Scans now, looking again for transcripts that were not found, and returns once what it found has reached
    /// the store. The debounce and the heartbeat run the same scan.
    func rescan() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                missingTranscripts = []
                scan()
                // The main queue runs in order, so this follows the batch `scan` handed it.
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    // MARK: Scanning

    private func beginWatching() {
        let fileManager = FileManager.default
        watchesClaude = claudeRoot.map { fileManager.fileExists(atPath: $0.path) } ?? false
        watchesCodex = codexRoot.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let roots = [watchesClaude ? claudeRoot : nil, watchesCodex ? codexRoot : nil].compactMap { $0 }
        if !roots.isEmpty {
            watch = fileSystem.watch(roots) { [weak self] paths in
                guard let self else { return }
                queue.async { [self] in
                    noteChanges(paths)
                    requestRescan()
                }
            }
        }
        heartbeatTimer = scheduler.every(heartbeat) { [weak self] in
            self?.missingTranscripts = []
            self?.scan()
        }
    }

    /// Lets a missing transcript be looked for again when something that could have created it changed: the
    /// file itself, a folder (which may be the new project's), or anything at all when the paths are unknown.
    /// Appends to other transcripts and registry updates, the bulk of the events, change nothing here.
    private func noteChanges(_ paths: [String]) {
        guard !missingTranscripts.isEmpty else { return }
        guard !paths.isEmpty else {
            missingTranscripts = []
            return
        }
        missingTranscripts = missingTranscripts.filter { sessionID in
            !paths.contains { path in
                let url = URL(filePath: path)
                return url.lastPathComponent == "\(sessionID).jsonl" || url.pathExtension.isEmpty
            }
        }
    }

    private func requestRescan() {
        guard !rescanScheduled else { return }
        rescanScheduled = true
        scheduler.after(debounce) { [self] in
            rescanScheduled = false
            scan()
        }
    }

    private func scan() {
        guard let generation = run.withLock({ $0.isRunning ? $0.generation : nil }) else { return }
        let now = now()
        var wanted: [URL: Target] = [:]
        var registry: [ClaudeSessionInfo]?
        if watchesClaude, let claudeRoot {
            let live = liveClaudeSessions(in: claudeRoot)
            for session in live {
                if let url = transcript(of: session.sessionID, in: claudeRoot, now: now) {
                    wanted[url] = Target(source: .claude, sessionID: session.sessionID)
                }
            }
            transcriptPaths = transcriptPaths.filter { id, _ in live.contains { $0.sessionID == id } }
            missingTranscripts = missingTranscripts.filter { id in live.contains { $0.sessionID == id } }
            if live != lastRegistry {
                lastRegistry = live
                registry = live
            }
        }
        if watchesCodex, let codexRoot {
            for (url, id) in recentRollouts(in: codexRoot, now: now) {
                wanted[url] = Target(source: .codex, sessionID: id)
            }
        }
        tracked = tracked.filter { wanted[$0.key] != nil }
        var events: [AgentEvent] = []
        for (url, target) in wanted where tracked[url] == nil {
            tracked[url] = startTracking(url, target: target)
        }
        for file in tracked.values {
            events += read(file)
        }
        deliver(events, registry: registry, generation: generation)
    }

    /// One batch per scan keeps the main actor's work to a single `apply`. The main queue keeps the order of batches.
    private func deliver(_ events: [AgentEvent], registry: [ClaudeSessionInfo]?, generation: Int) {
        guard !events.isEmpty || registry != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, run.withLock({ $0.isRunning && $0.generation == generation }) else { return }
            MainActor.assumeIsolated {
                store.apply(events)
                if let registry { store.updateRegistry(registry) }
            }
        }
    }

    // MARK: Claude

    /// The registry entries whose process is alive. A file caught half-written does not parse; its previous entry
    /// stands in, because losing it would end a running session and replay its transcript when it came back.
    private func liveClaudeSessions(in root: URL) -> [ClaudeSessionInfo] {
        let directory = root.appending(path: "sessions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var entries: [String: ClaudeSessionInfo] = [:]
        for name in names where name.hasSuffix(".json") {
            let data = try? Data(contentsOf: directory.appending(path: name))
            entries[name] = data.flatMap(ClaudeSessionRegistry.parse(data:)) ?? registryEntries[name]
        }
        registryEntries = entries
        return entries.values.filter { fileSystem.isAlive($0) }.sorted { ($0.sessionID, $0.pid) < ($1.sessionID, $1.pid) }
    }

    /// The transcript of a session, if it was written to recently.
    private func transcript(of sessionID: String, in root: URL, now: Date) -> URL? {
        // The id becomes a file name below `projects`; one that names a path is not a session.
        guard !sessionID.contains("/") else { return nil }
        var url = transcriptPaths[sessionID].flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        if url == nil, !missingTranscripts.contains(sessionID) {
            url = findTranscript(of: sessionID, in: root)
            if url == nil { missingTranscripts.insert(sessionID) }
        }
        guard let url else { return nil }
        transcriptPaths[sessionID] = url
        return isRecent(url, now: now) ? url : nil
    }

    /// Transcripts live in a folder named after the project's path, so look in each folder for the session's file.
    private func findTranscript(of sessionID: String, in root: URL) -> URL? {
        let projects = root.appending(path: "projects")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        return folders.lazy
            .map { projects.appending(path: $0).appending(path: "\(sessionID).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Codex

    /// Rollout files in the day folders around today that were written to recently. The folders are named by
    /// date, in local time or UTC, so a day on either side is included.
    private func recentRollouts(in root: URL, now: Date) -> [(URL, String)] {
        let calendar = Calendar.current
        var rollouts: [(URL, String)] = []
        for offset in -2...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = root.appending(path: String(format: "sessions/%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                guard let id = CodexRolloutParser.sessionID(fromFileName: name) else { continue }
                let url = folder.appending(path: name)
                if isRecent(url, now: now) { rollouts.append((url, id)) }
            }
        }
        return rollouts
    }

    // MARK: Reading

    private func isRecent(_ url: URL, now: Date) -> Bool {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return modified.map { now.timeIntervalSince($0) < Self.recentSeconds } ?? false
    }

    private func startTracking(_ url: URL, target: Target) -> TrackedFile {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value ?? 0
        let start = size > Self.tailBytes ? size - Self.tailBytes : 0
        var header: String?
        if target.source == .codex, start > 0 {
            header = try? makeTailer(url, 0).readNewLines(maxBytes: Self.headerBytes).first
        }
        return TrackedFile(
            target: target, url: url, tailer: makeTailer(url, start), header: header,
            awaitingFirstTotal: target.source == .codex && start == 0
        )
    }

    /// Everything appended since the last read, parsed. A file that cannot be read now is tried again next scan.
    private func read(_ file: TrackedFile) -> [AgentEvent] {
        var events: [AgentEvent] = []
        if let header = file.header {
            file.header = nil
            events += parse([header], in: file)
        }
        let stamp = FileStamp(of: file.url)
        if let stamp, stamp == file.readStamp { return events }
        file.readStamp = nil
        do {
            repeat {
                // One pool per piece, so the bytes and strings of a large append are freed as it goes.
                try autoreleasepool {
                    events += parse(try file.tailer.readNewLines(maxBytes: Self.chunkBytes), in: file)
                }
            } while file.tailer.hasMoreToRead
        } catch {
            return events
        }
        file.readStamp = stamp
        return events
    }

    /// A transcript file is one session, so its events take the file's session id even when a record names another.
    private func parse(_ lines: [String], in file: TrackedFile) -> [AgentEvent] {
        lines.flatMap { line -> [AgentEvent] in
            var events = file.codexParser != nil
                ? file.codexParser?.parse(line: line) ?? []
                : ClaudeTranscriptParser.parse(line: line, sessionID: file.target.sessionID)
            for index in events.indices {
                events[index].sessionID = file.target.sessionID
                if file.awaitingFirstTotal, events[index].usage?.isCumulative == true {
                    events[index].usage?.startsFromZero = true
                    file.awaitingFirstTotal = false
                }
            }
            return events
        }
    }
}
