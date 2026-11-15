import CoreGraphics
import MyNotchCore

extension ModuleRegistry {
    /// Content height for `state`: the height the shown tab asks for, the default otherwise. Under a toast that is the
    /// covered tab's height, so the notch does not shrink for the toast and the hidden tab is not squeezed. It is what
    /// the tab asked for, which the registry has held to `NotchTab.heightRange`; `NotchGeometry` holds it to the same range, so
    /// a tab that keeps to it is never cut.
    func contentHeight(for state: NotchState, tabUnderToast: ModuleID?) -> CGFloat {
        // The grid of "Khác" is as tall as its pages need.
        if state.shownTab(tabUnderToast: tabUnderToast) == NotchPages.moreID, pages.hasMore {
            return MoreTabGrid.contentHeight(pageCount: pages.overflow.count)
        }
        guard let id = state.shownTab(tabUnderToast: tabUnderToast), let tab = tabs.first(where: { $0.id == id }) else {
            return NotchTab.defaultHeight
        }
        return tab.preferredHeight ?? NotchTab.defaultHeight
    }
}
