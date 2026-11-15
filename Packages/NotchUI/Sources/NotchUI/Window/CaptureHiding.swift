import AppKit
import Observation

/// When the notch's windows stay out of screen recordings and shared screens.
nonisolated public enum CaptureHiding: String, Codable, Sendable, CaseIterable {
    case never
    /// Hidden while the notch is closed, compact or off screen; shown while it is open or a toast is up.
    case whenCollapsed
    case always

    /// `.none` keeps the window's contents from every other process (recorders, screen sharing); `.readOnly` is how
    /// a window normally behaves. A notch that is hidden is closed, so "collapsed" covers it too.
    public func sharingType(for state: NotchState) -> NSWindow.SharingType {
        switch self {
        case .never: .readOnly
        case .always: .none
        case .whenCollapsed: state.isExpanded ? .readOnly : .none
        }
    }
}

extension NSWindow.SharingType {
    /// For the log.
    var logName: String {
        switch self {
        case .none: "none"
        case .readOnly: "readOnly"
        // `readWrite` is deprecated and nothing here sets it.
        @unknown default: "other(\(rawValue))"
        }
    }
}

/// Keeps a window of MyNotch that is not the notch's own panel out of recordings the way the user asked, as the notch's
/// panels are: before the window can be shown (the follower is made first), and again at every change of the setting.
/// `state` is the notch state the window stands for: a widget under the collapsed notch is `.compact`, so "when
/// collapsed" hides it; something that only exists while the notch is expanded is `.toast`, so it stays visible then.
public final class CaptureHidingFollower {
    private var observation: Task<Void, Never>?

    /// Only holds the window weakly: the follower never keeps a window alive.
    public init(_ window: NSWindow, as state: NotchState, interface: NotchInterface = .shared) {
        window.sharingType = interface.captureHiding.sharingType(for: state)
        observation = Task { [weak window] in
            for await hiding in Observations({ interface.captureHiding }) {
                window?.sharingType = hiding.sharingType(for: state)
            }
        }
    }

    /// Stops following; the window keeps the sharing type it has. Call it when the window goes.
    public func stop() {
        observation?.cancel()
        observation = nil
    }

    deinit {
        observation?.cancel()
    }
}
