import Foundation
import Synchronization

/// What the `mynotch-youtube-host` executable does: Chrome starts it for the extension and writes native messages to
/// its stdin; it checks each one and passes it on to the app over a socket. The other way, the app may send a command
/// (next or previous, see `YouTubeCommand`, or one for a tab with media, see `TabCommand`) on that socket; the host checks it
/// and writes it to stdout, which is Chrome's channel back to the extension. Nothing else is ever written to stdout, and nothing to stderr, and the host never
/// fails: Chrome would only show the extension an error. What it does goes to the unified log instead (see `YouTubeBridgeLog`).
public enum YouTubeHostCLI {
    /// How often the host tries to reach the app again while it is away, and how soon it notices the app quitting.
    public static let reconnectInterval: TimeInterval = 2

    /// Runs until `stdin` ends, which is Chrome closing the extension's port; always returns 0.
    ///
    /// The host remembers the latest captions of up to three videos, the latest playback, the latest report of the
    /// extension's access to YouTube and the latest report of each page with media, and sends them first whenever it
    /// (re)connects, so an app that was started or restarted after the page loaded its captions still gets them.
    /// - Parameters:
    ///   - now: a monotonic clock in seconds, for the age of the playback to replay and for the pace of the log.
    ///   - expectedOwner: the user the socket's folder and file, and the process that listens, must belong to (see `UnixStreamSocket.open`).
    ///   - log: where the host reports itself and the extension's diagnostics.
    ///   - launch: how the host was started, for the first line of the log.
    ///   - commandOutput: where the commands of the app go, as native messages: Chrome's channel back to the extension.
    public static func run<Source: ByteReading>(
        stdin: Source,
        socketPath: String,
        reconnectInterval: TimeInterval = YouTubeHostCLI.reconnectInterval,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        expectedOwner: uid_t = geteuid(),
        log: YouTubeBridgeLog = .system,
        launch: YouTubeHostLaunch = .current,
        commandOutput: any ByteWriting = FileDescriptorWriter(fileDescriptor: STDOUT_FILENO)
    ) -> Int32 {
        run(
            stdin: stdin, socketPath: socketPath, reconnectInterval: reconnectInterval, now: now, expectedOwner: expectedOwner,
            peerUser: expectedOwner, log: log, launch: launch, commandOutput: commandOutput, didHandle: nil, didRound: nil
        )
    }

    /// `run` with a hook that is called after each native message has been dealt with (forwarded, kept for the replay or
    /// dropped). It is how a test learns that the host has got to a message, which the pipe alone does not say: a
    /// message written to stdin may not have been read yet. Another hook is called after each round of the thread that
    /// keeps the connection up, which is how a test learns that the host has tried again while the app is away.
    static func run<Source: ByteReading>(
        stdin: Source,
        socketPath: String,
        reconnectInterval: TimeInterval,
        now: @escaping @Sendable () -> TimeInterval,
        expectedOwner: uid_t,
        peerUser: uid_t,
        log: YouTubeBridgeLog,
        launch: YouTubeHostLaunch,
        commandOutput: any ByteWriting,
        didHandle: (@Sendable () -> Void)?,
        didRound: (@Sendable () -> Void)?
    ) -> Int32 {
        log("host start argc=\(launch.argumentCount) parent=\(launch.parentName ?? "unknown")")
        let relay = HostRelay(
            socketPath: socketPath, expectedOwner: expectedOwner, peerUser: peerUser, retryInterval: reconnectInterval, now: now,
            log: log, commandOutput: commandOutput, didRound: didRound
        )
        relay.start(reconnectingEvery: reconnectInterval)
        var reader = NativeMessageReader(source: stdin)
        loop: while true {
            switch reader.next() {
            case .message(let message):
                relay.submit(message)
                didHandle?()
            case .tooLarge:
                // A length Chrome never sends means the stream is out of step: nothing more can be read from it.
                log("host stdin out of step: length above the limit")
                break loop
            case .end:
                log("host stdin closed")
                break loop
            }
        }
        relay.stop()
        return 0
    }
}

/// The connection to the app and what is replayed over it. Messages arrive on the thread that reads stdin, and a
/// second thread keeps the connection up; one lock covers both, so a replay and a new message never interleave. Each
/// connection also has a thread of its own that waits for commands from the app and learns that the app has gone.
final class HostRelay: Sendable {
    /// Captions of this many videos are kept; the one least recently received goes first.
    static let maxVideos = 3
    /// A playback older than this is not replayed: the page sends one every 5 s while it plays, so an older one says
    /// nothing about now, and the app only trusts playback that is at most this old.
    static let maxPlaybackAge: TimeInterval = 10
    /// While the app stays away the log says so again this often, not at every try.
    static let awayReminderInterval: TimeInterval = 30
    /// Pages with media that are kept for the replay; a page is one only while it reports, so this is a bound, not a count.
    static let maxTabs = 64
    /// A page's report older than this is not replayed: a page that plays says so every 5 s and a paused one every 30 s (Chrome may put a
    /// background tab's timers to one a minute), the app stamps what it is given with the time it arrives, and an old report would show
    /// a position that far behind and keep a page that is gone that much longer.
    static let maxTabAge: TimeInterval = 60

    private struct State {
        var socket: Int32?
        /// Whole frames, oldest first, one per video.
        var captions: [(videoID: String, frame: Data)] = []
        var playback: (frame: Data, receivedAt: TimeInterval)?
        /// The latest report of each page that has media, oldest first, until the page says it has none or its tab closes.
        var tabs: [(tab: Int, frame: Data, receivedAt: TimeInterval)] = []
        /// The latest report of the extension's access to YouTube (`sw-access`): said once when its worker starts, which is
        /// about when the host does, so the app may not be there yet.
        var access: Data?
        /// Tries in a row that did not reach the app, and when the log last said so.
        var failedAttempts = 0
        var lastReminder: TimeInterval?
    }

    private let socketPath: String
    private let expectedOwner: uid_t
    private let peerUser: uid_t
    private let retryInterval: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let log: YouTubeBridgeLog
    private let commandOutput: any ByteWriting
    private let tally: FrameTally
    /// Called after each round of the thread that keeps the connection up (for tests).
    private let didRound: (@Sendable () -> Void)?
    private let state = Mutex(State())
    private let wake = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    /// The threads that read the connections, so that `stop` leaves none behind.
    private let readers = DispatchGroup()

    init(
        socketPath: String, expectedOwner: uid_t, peerUser: uid_t, retryInterval: TimeInterval,
        now: @escaping @Sendable () -> TimeInterval, log: YouTubeBridgeLog, commandOutput: any ByteWriting,
        didRound: (@Sendable () -> Void)? = nil
    ) {
        self.socketPath = socketPath
        self.expectedOwner = expectedOwner
        self.peerUser = peerUser
        self.retryInterval = retryInterval
        self.now = now
        self.log = log
        self.commandOutput = commandOutput
        self.didRound = didRound
        tally = FrameTally(counted: "forwarded", lost: "dropped", now: now)
    }

    func start(reconnectingEvery interval: TimeInterval) {
        Thread.detachNewThread { [self] in
            repeat { keepConnected() } while wake.wait(timeout: .now() + interval) == .timedOut
            finished.signal()
        }
    }

    /// Ends the connecting thread and closes the socket, and the thread that reads it.
    func stop() {
        wake.signal()
        finished.wait()
        state.withLock { state in
            guard state.socket != nil else { return }
            hangUp(&state)
            log("app socket closed: host exit")
        }
        readers.wait()
        if let summary = tally.line(force: true) { log("host frames \(summary)") }
    }

    /// Lets go of the connection: the thread that reads it wakes up and closes the socket. Only that thread closes a
    /// connection, so a descriptor is never closed under it while it waits in `recv`, and never reused by another socket
    /// while it still reads the old one.
    private func hangUp(_ state: inout State) {
        guard let socket = state.socket else { return }
        shutdown(socket, SHUT_RDWR)
        state.socket = nil
    }

    /// Checks a native message and, when it is valid and fits a frame, remembers what a later connection needs of it
    /// and sends it now. While the app is away nothing is sent: it is dropped.
    func submit(_ message: Data) {
        // The size comes first: a padded message of up to 64 MiB should be dropped, not parsed.
        guard let frame = AppFrame.encode(message) else {
            tally.lose("too-large")
            return
        }
        let parsed: YouTubeMessage
        switch YouTubeMessage.check(message) {
        case .success(let message): parsed = message
        case .failure(let rejection):
            tally.lose(rejection.rawValue)
            return
        }
        // Only an event that passed the grammar check is ever written down, so it holds nothing that must stay private.
        if case .diag(let diag) = parsed { log("extension diag where=\(diag.origin.rawValue) event=\(diag.event)") }
        state.withLock { state in
            switch parsed {
            case .captions(let captions):
                state.captions.removeAll { $0.videoID == captions.videoID }
                state.captions.append((captions.videoID, frame))
                if state.captions.count > Self.maxVideos { state.captions.removeFirst(state.captions.count - Self.maxVideos) }
            case .playback:
                state.playback = (frame, now())
            case .clear(let videoID):
                state.captions.removeAll { $0.videoID == videoID }
            case .tab(let tab):
                state.tabs.removeAll { $0.tab == tab.tab }
                state.tabs.append((tab.tab, frame, now()))
                if state.tabs.count > Self.maxTabs { state.tabs.removeFirst(state.tabs.count - Self.maxTabs) }
            case .tabGone(let tab):
                state.tabs.removeAll { $0.tab == tab }
            case .pageNames:
                // Said live, like a diagnostic: the page is asked again the next time its tab starts to make sound.
                break
            case .diag(let diag):
                // Said live: a diagnostic is about now, so it is not kept for a later connection. Except the access
                // report, which is a state the app shows until it changes.
                if diag.siteAccess != nil { state.access = frame }
            }
            guard let socket = state.socket else {
                tally.lose("app-away")
                return
            }
            if UnixStreamSocket.writeAll(frame, to: socket) {
                tally.count(parsed.typeName)
            } else {
                hangUp(&state)
                tally.lose("send-failed")
                log("app socket disconnected: send failed")
            }
        }
    }

    /// One round of the connecting thread: connects and replays when there is no connection. The connection's own
    /// thread notices the app going away.
    private func keepConnected() {
        state.withLock { state in
            guard state.socket == nil else { return }
            switch UnixStreamSocket.open(to: socketPath, fileOwner: expectedOwner, peerUser: peerUser) {
            case .failure(let failure):
                noteFailedAttempt(&state, reason: failure.reason)
            case .success(let socket):
                connected(socket, &state)
            }
        }
        if let summary = tally.line() { log("host frames \(summary)") }
        didRound?()
    }

    /// Sends the replay over a fresh connection, and keeps it when that worked.
    private func connected(_ socket: Int32, _ state: inout State) {
        var replay = state.captions.map(\.frame)
        let captionCount = replay.count
        var playbackIncluded = false
        if let playback = state.playback, now() - playback.receivedAt <= Self.maxPlaybackAge {
            replay.append(playback.frame)
            playbackIncluded = true
        }
        if let access = state.access { replay.append(access) }
        // A page that stopped reporting for good (its tab was discarded, say) is forgotten here, not replayed for ever.
        state.tabs.removeAll { now() - $0.receivedAt > Self.maxTabAge }
        replay.append(contentsOf: state.tabs.map(\.frame))
        guard replay.allSatisfy({ UnixStreamSocket.writeAll($0, to: socket) }) else {
            close(socket)
            noteFailedAttempt(&state, reason: "send-failed")
            return
        }
        state.socket = socket
        let after = state.failedAttempts > 0 ? " after-failed-attempts=\(state.failedAttempts)" : ""
        let tabs = state.tabs.isEmpty ? "" : " replayed-tabs=\(state.tabs.count)"
        state.failedAttempts = 0
        state.lastReminder = nil
        log("app socket connected replayed-captions=\(captionCount) replayed-playback=\(playbackIncluded)\(tabs)\(after)")
        readers.enter()
        Thread.detachNewThread { [self] in
            readCommands(from: socket)
            readers.leave()
        }
    }

    // MARK: commands from the app

    /// Waits for what the app sends on the connection, which is commands and nothing else, until the connection ends.
    private func readCommands(from socket: Int32) {
        var decoder = AppFrameDecoder(maxLength: YouTubeCommand.maxFrameLength)
        var buffer = [UInt8](repeating: 0, count: 512)
        var reason = "peer closed"
        reading: while true {
            let count = recv(socket, &buffer, buffer.count, 0)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                reason = "read failed"
                break
            }
            decoder.append(Data(buffer[0..<count]))
            while true {
                switch decoder.next() {
                case .needMore:
                    continue reading
                case .tooLarge:
                    // The stream is out of step, and no frame of it can be trusted any more.
                    reason = "command frame too large"
                    break reading
                case .frame(let frame):
                    forward(frame)
                }
            }
        }
        ended(socket, reason: reason)
    }

    /// Writes a command to Chrome, as the checked command: the bytes the app sent are never passed on.
    private func forward(_ frame: Data) {
        let json: Data
        let name: String
        if let command = YouTubeCommand.decode(frame) {
            json = command.json
            name = "action=\(command.rawValue)"
        } else if let command = TabCommand.decode(frame) {
            json = command.json
            name = "tab-action=\(command.action.word)"
        } else {
            log("command dropped reason=invalid")
            return
        }
        if commandOutput.write(NativeMessage.frame(json)) {
            log("command forwarded \(name)")
        } else {
            log("command not delivered: stdout closed")
        }
    }

    /// The connection is over, whoever ended it: the app, or the host itself (then `state.socket` is already gone and
    /// it has said so). The only place a connection is closed.
    private func ended(_ socket: Int32, reason: String) {
        state.withLock { state in
            if state.socket == socket {
                state.socket = nil
                log("app socket disconnected: \(reason)")
            }
            close(socket)
        }
    }

    /// The first failure after a connection (or the start) is logged, the following ones are a reminder every 30 s.
    private func noteFailedAttempt(_ state: inout State, reason: String) {
        state.failedAttempts += 1
        let current = now()
        if state.failedAttempts == 1 {
            state.lastReminder = current
            log("app socket unavailable reason=\(reason), trying again every \(Int(retryInterval))s")
        } else if let last = state.lastReminder, current - last >= Self.awayReminderInterval {
            state.lastReminder = current
            log("app socket still unavailable reason=\(reason) attempts=\(state.failedAttempts)")
        }
    }
}
