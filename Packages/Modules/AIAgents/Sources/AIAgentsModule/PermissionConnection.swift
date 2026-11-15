import AgentHookKit
import Foundation
import Synchronization

/// One helper waiting for the user's answer on the permission socket. It reads the helper's one request line, then
/// holds the connection open until it is answered, or the helper leaves. All of it may be called from any thread:
/// the socket is read on the server's private queue, the answer comes from the main actor.
nonisolated final class PermissionConnection: Sendable {
    private enum Phase: Equatable {
        /// Collecting the request line.
        case reading
        /// The request was handed on; the helper waits for an answer.
        case waiting
        /// Answered, dropped, or closed by the server: nothing more happens on this connection.
        case finished
    }

    private struct State {
        var phase = Phase.reading
        var buffer = Data()
        var peerClosed = false
        var onPeerClosed: (@MainActor @Sendable () -> Void)?
    }

    private enum Step {
        case keepReading, drop, deliver(HookPayload)
    }

    private let fd: Int32
    private let queue: DispatchQueue
    private let state = Mutex(State())
    private let source = Mutex<(any DispatchSourceRead)?>(nil)
    /// Tells the server this connection is over, so it stops counting it.
    private let onEnd: @Sendable (PermissionConnection) -> Void

    init(fd: Int32, queue: DispatchQueue, onEnd: @escaping @Sendable (PermissionConnection) -> Void) {
        self.fd = fd
        self.queue = queue
        self.onEnd = onEnd
    }

    /// Starts reading. `deliver` runs on the server's queue with the request, once, when a whole valid line came in;
    /// a connection that sends anything else, or too much, or nothing within `timeout`, is closed.
    func begin(timeout: TimeInterval, deliver: @escaping @Sendable (HookPayload) -> Void) {
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let handler: @Sendable () -> Void = { [self] in readAvailable(deliver) }
        reader.setEventHandler(handler: handler)
        let cancelHandler: @Sendable () -> Void = { [fd] in close(fd) }
        reader.setCancelHandler(handler: cancelHandler)
        source.withLock { $0 = reader }
        reader.resume()
        queue.asyncAfter(deadline: .now() + timeout) { [self] in
            if move(from: .reading) {
                cancelSource()
                onEnd(self)
            }
        }
    }

    /// Tells the helper the answer and closes. Only the first call counts, and one after the helper left is harmless.
    func reply(_ answer: PermissionAnswer) {
        guard move(from: .waiting) else { return }
        let line = Array(PermissionWire.replyLine(answer))
        // A few bytes into an empty socket buffer: it takes them at once, or the helper is gone and the write fails.
        // Written before the source is cancelled, since cancelling is what closes the socket.
        _ = write(fd, line, line.count)
        cancelSource()
        onEnd(self)
    }

    /// Runs `handler` on the main actor when the helper leaves while waiting, as when the user answered in the
    /// terminal and the agent stopped the hook. Also when it left before this was called.
    func onPeerClosed(_ handler: @escaping @MainActor @Sendable () -> Void) {
        let alreadyGone = state.withLock { state in
            if !state.peerClosed { state.onPeerClosed = handler }
            return state.peerClosed
        }
        if alreadyGone { Self.runOnMain(handler) }
    }

    /// Closes without an answer and without telling the handler: the app is the one that stops.
    func shutDown() {
        guard claim() != nil else { return }
        cancelSource()
    }

    // MARK: Reading

    private func readAvailable(_ deliver: @Sendable (HookPayload) -> Void) {
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                switch consume(buffer[0..<count]) {
                case .keepReading: continue
                case .drop:
                    onEnd(self)
                    return
                case let .deliver(payload):
                    deliver(payload)
                }
            } else if count < 0, errno == EAGAIN || errno == EINTR {
                return
            } else {
                helperLeft()
                return
            }
        }
    }

    /// Takes bytes while reading the request line. Bytes after it are not looked at.
    private func consume(_ bytes: ArraySlice<UInt8>) -> Step {
        let step = state.withLock { state -> Step in
            guard state.phase == .reading else { return .keepReading }
            state.buffer.append(contentsOf: bytes)
            guard let newline = state.buffer.firstIndex(of: UInt8(ascii: "\n")) else {
                if state.buffer.count > PermissionWire.maxRequestLength { state.phase = .finished; return .drop }
                return .keepReading
            }
            let line = state.buffer[state.buffer.startIndex..<newline]
            state.buffer = Data()
            guard line.count <= PermissionWire.maxRequestLength, let payload = PermissionWire.decodeRequest(line) else {
                state.phase = .finished
                return .drop
            }
            state.phase = .waiting
            return .deliver(payload)
        }
        if case .drop = step { cancelSource() }
        return step
    }

    private func helperLeft() {
        let left = state.withLock { state -> (wasWaiting: Bool, handler: (@MainActor @Sendable () -> Void)?)? in
            guard state.phase != .finished else { return nil }
            let wasWaiting = state.phase == .waiting
            state.phase = .finished
            state.peerClosed = wasWaiting
            return (wasWaiting, state.onPeerClosed)
        }
        // Already finished by an answer or a shutdown, whose owner closes the socket.
        guard let left else { return }
        cancelSource()
        onEnd(self)
        if left.wasWaiting, let handler = left.handler { Self.runOnMain(handler) }
    }

    // MARK: Ending

    /// Moves to `finished` and returns the phase it left; nil when it was already finished. Whoever moves it closes the
    /// socket, and only then: closing it while another thread is about to write an answer would send that answer to
    /// whatever got the descriptor next.
    private func claim() -> Phase? {
        state.withLock { state in
            guard state.phase != .finished else { return nil }
            defer { state.phase = .finished }
            return state.phase
        }
    }

    /// Moves to `finished` when the phase was `phase`; false when it was something else.
    private func move(from phase: Phase) -> Bool {
        state.withLock { state in
            guard state.phase == phase else { return false }
            state.phase = .finished
            return true
        }
    }

    /// The socket is closed by the source's cancel handler, once, after anything still reading has returned.
    private func cancelSource() {
        source.withLock { $0 }?.cancel()
    }

    private static func runOnMain(_ handler: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { handler() } }
    }
}
