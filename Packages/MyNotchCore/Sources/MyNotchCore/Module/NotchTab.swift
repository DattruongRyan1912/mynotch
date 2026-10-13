import SwiftUI

/// Content a running module shows when the notch is open.
public struct NotchTab: Identifiable {
    nonisolated public static let defaultHeight: CGFloat = 190
    nonisolated public static let heightRange: ClosedRange<CGFloat> = 120...300

    public let id: ModuleID
    public let title: String
    public let systemImage: String
    public let preferredHeight: CGFloat?
    public let content: AnyView

    public init(id: ModuleID, title: String, systemImage: String, preferredHeight: CGFloat? = nil, content: AnyView) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.preferredHeight = preferredHeight
        self.content = content
    }

    /// Content height after applying the default and the allowed range.
    public var contentHeight: CGFloat {
        min(max(preferredHeight ?? Self.defaultHeight, Self.heightRange.lowerBound), Self.heightRange.upperBound)
    }
}
