import Foundation

/// Tells when Low Power Mode is switched on or off, so the tab can follow it.
final class LowPowerModeObserver {
    private let center: NotificationCenter
    private var token: (any NSObjectProtocol)?

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    isolated deinit {
        stop()
    }

    /// Replaces an earlier callback.
    func start(_ onChange: @escaping @MainActor () -> Void) {
        stop()
        // Delivered on the main queue, which is where the tab and the module live.
        token = center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    func stop() {
        if let token { center.removeObserver(token) }
        token = nil
    }
}
