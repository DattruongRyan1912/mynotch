import CoreGraphics
import MyNotchCore

extension ModuleRegistry {
    /// Content height for `state`: the shown tab's clamped height, the default otherwise. Under a toast that is the
    /// covered tab's height, so the notch does not shrink for the toast and the hidden tab is not squeezed.
    func contentHeight(for state: NotchState, tabUnderToast: ModuleID?) -> CGFloat {
        guard let id = state.shownTab(tabUnderToast: tabUnderToast), let tab = tabs.first(where: { $0.id == id }) else {
            return NotchTab.defaultHeight
        }
        return tab.contentHeight
    }
}
