import SwiftUI

/// Lets tab content control the notch it is shown in (pin while a menu is open, report drags, close after an action).
public struct NotchHandle {
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

    public func close() {
        model?.close()
    }
}

extension EnvironmentValues {
    /// The notch the view is shown in; the default handle does nothing.
    @Entry public var notch: NotchHandle = NotchHandle()
}
