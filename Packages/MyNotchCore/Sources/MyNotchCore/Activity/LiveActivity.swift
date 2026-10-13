import SwiftUI

nonisolated public enum ActivityPriority: Int, Comparable, Sendable {
    case low, normal, high, critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Small content shown beside the notch while it is closed.
public struct LiveActivity: Identifiable {
    public let id: String
    public let priority: ActivityPriority
    public let leading: AnyView
    public let trailing: AnyView
    public let expiresAfter: Duration?

    public init(
        id: String,
        priority: ActivityPriority = .normal,
        expiresAfter: Duration? = nil,
        leading: AnyView,
        trailing: AnyView
    ) {
        self.id = id
        self.priority = priority
        self.expiresAfter = expiresAfter
        self.leading = leading
        self.trailing = trailing
    }
}
