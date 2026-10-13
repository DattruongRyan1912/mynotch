import SwiftUI

/// Lets tab content control the notch it is shown in (pin while a menu is open, report drags, close after an action).
public struct NotchHandle: Equatable {
    private weak var model: NotchViewModel?

    /// Without a model every call does nothing, which is what views outside a notch (previews, tests) get.
    init(model: NotchViewModel? = nil) {
        self.model = model
    }

    /// Keeps the notch open while the tab shows something outside it, such as a menu, popover or sheet.
    public func setPinned(_ pinned: Bool) {
        model?.isPinned = pinned
    }

    /// Keeps the notch open while a drag into or out of the tab is in progress.
    public func setDragging(_ dragging: Bool) {
        model?.setDragging(dragging)
    }

    /// Closes the notch, e.g. once the tab finished what the user opened it for (a paste, a dropped file).
    public func close() {
        model?.close()
    }

    /// Handles are equal when they control the same notch, so redrawing the root view changes nothing below it.
    nonisolated public static func == (lhs: NotchHandle, rhs: NotchHandle) -> Bool {
        lhs.model === rhs.model
    }
}

extension EnvironmentValues {
    /// The notch the view is shown in; the default handle does nothing.
    @Entry public var notch: NotchHandle = NotchHandle()
}
