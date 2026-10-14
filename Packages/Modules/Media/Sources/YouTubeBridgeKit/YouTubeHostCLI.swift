import Foundation
import Synchronization

/// What the `mynotch-youtube-host` executable does: Chrome starts it for the extension and writes native messages to
/// its stdin; it checks each one and passes it on to the app over a socket. It never writes to stdout or stderr
/// (stdout is Chrome's channel back to the extension, which gets nothing), and it never fails: Chrome would only
/// show the extension an error.
public enum YouTubeHostCLI {
    /// How often the host tries to reach the app again while it is away, and how soon it notices the app quitting.
    public static let reconnectInterval: TimeInterval = 2

    /// Runs until `stdin` ends, which is Chrome closing the extension's port; always returns 0.
    ///
    /// The host remembers the latest captions of up to three videos and the latest playback, and sends them first
    /// whenever it (re)connects, so an app that was started or restarted after the page loaded its captions still gets them.
    /// - Parameters:
    ///   - now: a monotonic clock in seconds, for the age of the playback to replay.
    ///   - expectedOwner: the user the socket file must belong to.
    public static func run<Source: ByteReading>(
        stdin: Source,
        socketPath: String,
        reconnectInterval: TimeInterval = YouTubeHostCLI.reconnectInterval,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        expectedOwner: uid_t = geteuid()
    ) -> Int32 {
        let relay = HostRelay(socketPath: socketPath, expectedOwner: expectedOwner, now: now)
        relay.start(reconnectingEvery: reconnectInterval)
        var reader = NativeMessageReader(source: stdin)
        loop: while true {
            switch reader.next() {
            case .message(let message): relay.submit(message)
            // A length Chrome never sends means the stream is out of step: nothing more can be read from it.
            case .tooLarge, .end: break loop
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

    private struct State {
        var socket: Int32?
        /// Whole frames, oldest first, one per video.
        var captions: [(videoID: String, frame: Data)] = []
        var playback: (frame: Data, receivedAt: TimeInterval)?
    }

    private let socketPath: String
    private let expectedOwner: uid_t
    private let now: @Sendable () -> TimeInterval
    private let state = Mutex(State())
    private let wake = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)

    init(socketPath: String, expectedOwner: uid_t, now: @escaping @Sendable () -> TimeInterval) {
        self.socketPath = socketPath
        self.expectedOwner = expectedOwner
        self.now = now
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
            if let socket = state.socket { close(socket) }
            state.socket = nil
        }
    }

    /// Checks a native message and, when it is valid and fits a frame, remembers what a later connection needs of it
    /// and sends it now. While the app is away nothing is sent: it is dropped.
    func submit(_ message: Data) {
        // The size comes first: a padded message of up to 64 MiB should be dropped, not parsed.
        guard let frame = AppFrame.encode(message), let parsed = YouTubeMessage.decode(message) else { return }
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
            }
            if let socket = state.socket, !UnixStreamSocket.writeAll(frame, to: socket) {
                close(socket)
                state.socket = nil
            }
        }
    }

    /// One round of the connecting thread: notices a closed socket, and connects and replays when there is none.
    private func keepConnected() {
        state.withLock { state in
            if let socket = state.socket, UnixStreamSocket.peerHasClosed(socket) {
                close(socket)
                state.socket = nil
            }
            guard state.socket == nil, let socket = UnixStreamSocket.connect(to: socketPath, expectedOwner: expectedOwner) else { return }
            var replay = state.captions.map(\.frame)
            if let playback = state.playback, now() - playback.receivedAt <= Self.maxPlaybackAge { replay.append(playback.frame) }
            guard replay.allSatisfy({ UnixStreamSocket.writeAll($0, to: socket) }) else {
                close(socket)
                return
            }
            state.socket = socket
        }
    }
}
