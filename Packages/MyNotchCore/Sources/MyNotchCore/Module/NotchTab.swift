import SwiftUI
import UniformTypeIdentifiers

/// Content a running module shows when the notch is open.
public struct NotchTab: Identifiable {
    nonisolated public static let defaultHeight: CGFloat = 190
    nonisolated public static let heightRange: ClosedRange<CGFloat> = 120...300

    public let id: ModuleID
    public let title: String
    public let systemImage: String
    /// Height of the area below the notch, including the notch's inner padding (14pt) and, when two or more tabs exist, the tab bar (30pt).
    public let preferredHeight: CGFloat?
    /// Set by tabs with text fields or keyboard navigation. The notch panel then takes keyboard focus
    /// while the tab is shown, without activating MyNotch, so the app in front stays active.
    public let acceptsKeyboard: Bool
    /// Types the tab accepts when something is dropped on the notch, even while it is closed. The notch opens
    /// the first tab whose types match what is being dragged.
    public let dropTypes: [UTType]
    /// Receives the dropped items; returns whether they were accepted.
    public let onDrop: (([NSItemProvider]) -> Bool)?
    public let content: AnyView

    public init(
        id: ModuleID,
        title: String,
        systemImage: String,
        preferredHeight: CGFloat? = nil,
        acceptsKeyboard: Bool = false,
        dropTypes: [UTType] = [],
        onDrop: (([NSItemProvider]) -> Bool)? = nil,
        content: AnyView
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.preferredHeight = preferredHeight
        self.acceptsKeyboard = acceptsKeyboard
        self.dropTypes = dropTypes
        self.onDrop = onDrop
        self.content = content
    }

    /// Content height after applying the default and the allowed range.
    public var contentHeight: CGFloat {
        min(max(preferredHeight ?? Self.defaultHeight, Self.heightRange.lowerBound), Self.heightRange.upperBound)
    }
}

/// The order of the tabs in the open notch, as the user arranged them. Both functions are plain list arithmetic so the
/// rules (what a new or a removed module does to a stored order) are checked without a registry.
nonisolated public enum TabOrder {
    /// `available` (module order) arranged by `stored`: stored ids that are available first, in stored order, then the
    /// rest in module order, so a module with no stored position goes last and a stored id nobody runs is skipped.
    public static func merged(stored: [ModuleID], available: [ModuleID]) -> [ModuleID] {
        let known = Set(available)
        var seen: Set<ModuleID> = []
        return (stored.filter(known.contains) + available).filter { seen.insert($0).inserted }
    }

    /// What to store once the user arranged the tabs on screen as `visible`: that order, then the ids that were stored
    /// but are not on screen (a module that is switched off) in their old order, so their place survives for later.
    public static func updated(stored: [ModuleID], visible: [ModuleID]) -> [ModuleID] {
        var seen: Set<ModuleID> = []
        return (visible + stored).filter { seen.insert($0).inserted }
    }
}
