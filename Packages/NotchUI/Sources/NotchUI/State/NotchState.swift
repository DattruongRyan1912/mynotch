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

    /// The tab on screen: the open one, or under a toast the tab it covers and keeps alive.
    func shownTab(tabUnderToast: ModuleID?) -> ModuleID? {
        switch self {
        case .open(let id): id
        case .toast: tabUnderToast
        case .closed, .compact: nil
        }
    }
}
