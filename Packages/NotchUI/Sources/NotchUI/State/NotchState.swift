import MyNotchCore

nonisolated public enum NotchState: Equatable, Sendable {
    case closed
    case compact
    case open(ModuleID?)
    case toast

    public var isExpanded: Bool {
        switch self {
        case .open, .toast: true
        case .closed, .compact: false
        }
    }
}
