import Foundation
import Synchronization

/// What the `mynotch-youtube-host` executable does: Chrome starts it for the extension and writes native messages to
/// its stdin; it checks each one and passes it on to the app over a socket. It never writes to stdout or stderr
/// (stdout is Chrome's channel back to the extension, which gets nothing), and it never fails: Chrome would only
/// show the extension an error. What it does goes to the unified log instead (see `YouTubeBridgeLog`).
public enum YouTubeHostCLI {
    /// How often the host tries to reach the app again while it is away, and how soon it notices the app quitting.
    public static let reconnectInterval: TimeInterval = 2

    /// Runs until `stdin` ends, which is Chrome closing the extension's port; always returns 0.
    ///
    /// The host remembers the latest captions of up to three videos and the latest playback, and sends them first
    /// whenever it (re)connects, so an app that was started or restarted after the page loaded its captions still gets them.
    /// - Parameters:
    ///   - now: a monotonic clock in seconds, for the age of the playback to replay and for the pace of the log.
    ///   - expectedOwner: the user the socket file must belong to.
    ///   - log: where the host reports itself and the extension's diagnostics.
    ///   - launch: how the host was started, for the first line of the log.
    public static func run<Source: ByteReading>(
        stdin: Source,
        socketPath: String,
        reconnectInterval: TimeInterval = YouTubeHostCLI.reconnectInterval,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        expectedOwner: uid_t = geteuid(),
        log: YouTubeBridgeLog = .system,
        launch: YouTubeHostLaunch = .current
    ) -> Int32 {
        log("host start argc=\(launch.argumentCount) parent=\(launch.parentName ?? "unknown")")
        let relay = HostRelay(socketPath: socketPath, expectedOwner: expectedOwner, retryInterval: reconnectInterval, now: now, log: log)
        relay.start(reconnectingEvery: reconnectInterval)
        var reader = NativeMessageReader(source: stdin)
        loop: while true {
            switch reader.next() {
            case .message(let message):
                relay.submit(message)
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
/// second thread keeps the connection up; one lock covers both, so a replay and a new message never interleave.
final class HostRelay: Sendable {
    /// Captions of this many videos are kept; the one least recently received goes first.
    static let maxVideos = 3
    /// A playback older than this is not replayed: the page sends one every 5 s while it plays, so an older one says
    /// nothing about now, and the app only trusts playback that is at most this old.
    static let maxPlaybackAge: TimeInterval = 10
    /// While the app stays away the log says so again this often, not at every try.
    static let awayReminderInterval: TimeInterval = 30

    private struct State {
        var socket: Int32?
        /// Whole frames, oldest first, one per video.
        var captions: [(videoID: String, frame: Data)] = []
        var playback: (frame: Data, receivedAt: TimeInterval)?
        /// Tries in a row that did not reach the app, and when the log last said so.
        var failedAttempts = 0
        var lastReminder: TimeInterval?
    }

    private let socketPath: String
    private let expectedOwner: uid_t
    private let retryInterval: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let log: YouTubeBridgeLog
    private let tally: FrameTally
    private let state = Mutex(State())
    private let wake = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)

    init(
        socketPath: String, expectedOwner: uid_t, retryInterval: TimeInterval,
        now: @escaping @Sendable () -> TimeInterval, log: YouTubeBridgeLog
    ) {
        self.socketPath = socketPath
        self.expectedOwner = expectedOwner
        self.retryInterval = retryInterval
        self.now = now
        self.log = log
        tally = FrameTally(counted: "forwarded", lost: "dropped", now: now)
    }

    func start(reconnectingEvery interval: TimeInterval) {
        Thread.detachNewThread { [self] in
            repeat { keepConnected() } while wake.wait(timeout: .now() + interval) == .timedOut
            finished.signal()
        }
    }

    /// Ends the connecting thread and closes the socket.
    func stop() {
        wake.signal()
        finished.wait()
        state.withLock { state in
            guard let socket = state.socket else { return }
            close(socket)
            state.socket = nil
            log("app socket closed: host exit")
        }
        if let summary = tally.line(force: true) { log("host frames \(summary)") }
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
            case .diag:
                // Said once, live: a diagnostic is about now, so it is not kept for a later connection.
                break
            }
            guard let socket = state.socket else {
                tally.lose("app-away")
                return
            }
            if UnixStreamSocket.writeAll(frame, to: socket) {
                tally.count(parsed.typeName)
            } else {
                close(socket)
                state.socket = nil
                tally.lose("send-failed")
                log("app socket disconnected: send failed")
            }
        }
    }

    /// One round of the connecting thread: notices a closed socket, and connects and replays when there is none.
    private func keepConnected() {
        state.withLock { state in
            if let socket = state.socket, UnixStreamSocket.peerHasClosed(socket) {
                close(socket)
                state.socket = nil
                log("app socket disconnected: peer closed")
            }
            guard state.socket == nil else { return }
            switch UnixStreamSocket.open(to: socketPath, expectedOwner: expectedOwner) {
            case .failure(let failure):
                noteFailedAttempt(&state, reason: failure.reason)
            case .success(let socket):
                connected(socket, &state)
            }
        }
        if let summary = tally.line() { log("host frames \(summary)") }
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
        guard replay.allSatisfy({ UnixStreamSocket.writeAll($0, to: socket) }) else {
            close(socket)
            noteFailedAttempt(&state, reason: "send-failed")
            return
        }
        state.socket = socket
        let after = state.failedAttempts > 0 ? " after-failed-attempts=\(state.failedAttempts)" : ""
        state.failedAttempts = 0
        state.lastReminder = nil
        log("app socket connected replayed-captions=\(captionCount) replayed-playback=\(playbackIncluded)\(after)")
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
