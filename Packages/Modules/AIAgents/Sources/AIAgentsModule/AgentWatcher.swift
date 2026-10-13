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

    private nonisolated final class TrackedFile {
        let target: Target
        let tailer: JSONLTailer
        var codexParser: CodexRolloutParser?
        /// A Codex rollout joined mid-way: its first line, which names the working directory and branch.
        var header: String?
        /// A Codex rollout read from its first line: its first running total is all of the session's usage.
        var awaitingFirstTotal: Bool

        init(target: Target, tailer: JSONLTailer, header: String?, awaitingFirstTotal: Bool) {
            self.target = target
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
    private let now: @Sendable () -> Date
    private let debounce: DispatchTimeInterval
    private let heartbeat: DispatchTimeInterval
    private let queue = DispatchQueue(label: "io.lucasvu.mynotch.aiagents.watcher", qos: .utility)
    /// Read on the main queue too, to drop what a stopped watcher had already queued.
    private let isRunning = Mutex(false)

    // Everything below belongs to `queue`.
    private var watch: (any AgentWatchHandle)?
    private var heartbeatTimer: DispatchSourceTimer?
    private var rescanScheduled = false
    private var watchesClaude = false
    private var watchesCodex = false
    private var tracked: [URL: TrackedFile] = [:]
    private var transcriptPaths: [String: URL] = [:]
    private var lastRegistry: [ClaudeSessionInfo]?
    /// The last entry read from each registry file, by file name.
    private var registryEntries: [String: ClaudeSessionInfo] = [:]

    /// - Parameters:
    ///   - claudeRoot: `~/.claude`, or nil to leave Claude Code out.
    ///   - codexRoot: `~/.codex`, or nil to leave Codex out.
    ///   - debounce: how long after a file event the rescan waits, so a burst of writes costs one scan.
    ///   - heartbeat: how often to rescan without an event. A process that dies leaves its registry file behind
    ///     and touches no file, so only polling notices.
    init(
        store: AgentSessionStore,
        claudeRoot: URL?,
        codexRoot: URL?,
        fileSystem: any AgentFileSystem = LocalAgentFileSystem(),
        now: @escaping @Sendable () -> Date = { Date() },
        debounce: DispatchTimeInterval = .milliseconds(100),
        heartbeat: DispatchTimeInterval = .seconds(10)
    ) {
        self.store = store
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
        self.fileSystem = fileSystem
        self.now = now
        self.debounce = debounce
        self.heartbeat = heartbeat
    }

    /// Starts watching the roots that exist now; a missing one (Codex not installed) stays off until the next start.
    func start() {
        queue.async { [self] in
            guard !isRunning.withLock({ running in defer { running = true }; return running }) else { return }
            beginWatching()
            scan()
        }
    }

    /// Stops reading and forgets every file offset. Nothing reaches the store after this returns.
    func stop() {
        queue.sync {
            isRunning.withLock { $0 = false }
            watch?.cancel()
            watch = nil
            heartbeatTimer?.cancel()
            heartbeatTimer = nil
            rescanScheduled = false
            tracked = [:]
            transcriptPaths = [:]
            lastRegistry = nil
            registryEntries = [:]
        }
    }

    /// Scans now and returns once what it found has reached the store. The debounce and the heartbeat run the same scan.
    func rescan() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
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
            watch = fileSystem.watch(roots) { [weak self] in
                guard let self else { return }
                queue.async { [self] in requestRescan() }
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + heartbeat, repeating: heartbeat, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.scan() }
        timer.resume()
        heartbeatTimer = timer
    }

    private func requestRescan() {
        guard !rescanScheduled else { return }
        rescanScheduled = true
        queue.asyncAfter(deadline: .now() + debounce) { [self] in
            rescanScheduled = false
            scan()
        }
    }

    private func scan() {
        guard isRunning.withLock({ $0 }) else { return }
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
        deliver(events, registry: registry)
    }

    /// One batch per scan keeps the main actor's work to a single `apply`. The main queue keeps the order of batches.
    private func deliver(_ events: [AgentEvent], registry: [ClaudeSessionInfo]?) {
        guard !events.isEmpty || registry != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, isRunning.withLock({ $0 }) else { return }
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
        let known = transcriptPaths[sessionID].flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        guard let url = known ?? findTranscript(of: sessionID, in: root) else { return nil }
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
            header = try? JSONLTailer(url: url).readNewLines(maxBytes: Self.headerBytes).first
        }
        return TrackedFile(
            target: target, tailer: JSONLTailer(url: url, startOffset: start), header: header,
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
        do {
            repeat {
                let lines = try file.tailer.readNewLines(maxBytes: Self.chunkBytes)
                events += parse(lines, in: file)
            } while file.tailer.hasMoreToRead
        } catch {
            return events
        }
        return events
    }

    /// A transcript file is one session, so its events take the file's session id even when a record names another.
    private func parse(_ lines: [String], in file: TrackedFile) -> [AgentEvent] {
        autoreleasepool {
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
}
