import CoreGraphics
import MyNotchCore

extension ModuleRegistry {
    /// Content height for `state`: the height the shown tab asks for, the default otherwise. Under a toast that is the
    /// covered tab's height, so the notch does not shrink for the toast and the hidden tab is not squeezed. It is what
    /// the tab asked for, not held to a range: `NotchGeometry` holds it between the least a tab gets and the user's max
    /// height, so that setting decides how tall a tall tab can get.
    func contentHeight(for state: NotchState, tabUnderToast: ModuleID?) -> CGFloat {
        guard let id = state.shownTab(tabUnderToast: tabUnderToast), let tab = tabs.first(where: { $0.id == id }) else {
            return NotchTab.defaultHeight
        }
        return tab.preferredHeight ?? NotchTab.defaultHeight
    }
}
