import CoreGraphics
import MyNotchCore

extension ModuleRegistry {
    /// Content height for `state`: the selected tab's clamped height when open, the default otherwise.
    func contentHeight(for state: NotchState) -> CGFloat {
        guard case .open(let id) = state, let tab = tabs.first(where: { $0.id == id }) else {
            return NotchTab.defaultHeight
        }
        return tab.contentHeight
    }
}
