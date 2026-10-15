import AppKit

/// The light tap on the trackpad that goes with a gesture.
nonisolated public enum Haptic: Sendable, Equatable {
    /// Two things lining up: a tab that took its place, a window that snapped into a tile.
    case alignment
    /// A step from one level to another: the notch opening or closing.
    case levelChange

    var pattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .alignment: .alignment
        case .levelChange: .levelChange
        }
    }
}

/// Where taps go; a test puts its own in place of the system's.
public protocol HapticPerformer {
    func perform(_ haptic: Haptic)
}

/// The system's own performer. A trackpad without Force Touch, and a mouse, feel nothing, which is as it should be.
public struct SystemHapticPerformer: HapticPerformer {
    public init() {}

    public func perform(_ haptic: Haptic) {
        NSHapticFeedbackManager.defaultPerformer.perform(haptic.pattern, performanceTime: .now)
    }
}
