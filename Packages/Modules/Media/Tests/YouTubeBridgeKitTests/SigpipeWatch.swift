import Darwin
import Foundation
import Synchronization

/// SIGPIPEs seen since the process began, while a `SigpipeWatch` is alive.
private let sigpipes = Atomic<Int>(0)

/// Counts SIGPIPE instead of letting it end the process (its default action), so that a send to a closed socket that
/// is not guarded against it fails the test that did it rather than taking the whole test run down. Tests run in
/// parallel and share the signal's handler, so the first watch installs it and the last one puts the old one back.
final class SigpipeWatch: Sendable {
    private struct Installation {
        var watches = 0
        var previous = sigaction()
    }

    private static let installation = Mutex(Installation())
    private let baseline = sigpipes.load(ordering: .relaxed)

    init() {
        Self.installation.withLock { installation in
            if installation.watches == 0 {
                var action = sigaction()
                action.__sigaction_u.__sa_handler = { _ in sigpipes.add(1, ordering: .relaxed) }
                sigemptyset(&action.sa_mask)
                sigaction(SIGPIPE, &action, &installation.previous)
            }
            installation.watches += 1
        }
    }

    deinit {
        Self.installation.withLock { installation in
            installation.watches -= 1
            if installation.watches == 0 { sigaction(SIGPIPE, &installation.previous, nil) }
        }
    }

    /// SIGPIPEs raised since this watch was made.
    var count: Int { sigpipes.load(ordering: .relaxed) - baseline }
}
