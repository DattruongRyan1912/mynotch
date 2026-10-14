import AppKit

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
