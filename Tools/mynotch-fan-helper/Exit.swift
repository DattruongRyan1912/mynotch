import Foundation

/// What runs when the process ends by `exit()`, whoever calls it: gives the fans back to Apple. A C callback cannot capture, so it is
/// held here.
nonisolated(unsafe) var restoreBeforeExit: (@Sendable () -> Void)?

nonisolated func installExitHandler() {
    atexit { restoreBeforeExit?() }
}
