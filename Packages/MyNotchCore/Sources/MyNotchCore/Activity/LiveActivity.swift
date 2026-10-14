import SwiftUI

nonisolated public enum ActivityPriority: Int, Comparable, Sendable {
    case low, normal, high, critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Small content shown beside the notch while it is closed, and optionally a strip under it.
public struct LiveActivity: Identifiable {
    public let id: String
    public let priority: ActivityPriority
    public let leading: AnyView
    public let trailing: AnyView
    /// Content for a strip under the closed notch, shown while this is the current activity. The notch grows
    /// downward by `bottomHeight` to hold it; nil leaves the notch as it is.
    public let bottom: AnyView?
    /// How tall the strip is, in points. 0 whenever there is no `bottom`, so the two can never disagree.
    public let bottomHeight: CGFloat
    public let expiresAfter: Duration?

    /// Whether the notch has a strip to make room for: there is a view and it has a height.
    public var hasBottom: Bool { bottom != nil && bottomHeight > 0 }

    public init(
        id: String,
        priority: ActivityPriority = .normal,
        expiresAfter: Duration? = nil,
        leading: AnyView,
        trailing: AnyView,
        bottom: AnyView? = nil,
        bottomHeight: CGFloat = 0
    ) {
        self.id = id
        self.priority = priority
        self.expiresAfter = expiresAfter
        self.leading = leading
        self.trailing = trailing
        self.bottom = bottom
        self.bottomHeight = bottom == nil ? 0 : max(bottomHeight, 0)
    }
}
