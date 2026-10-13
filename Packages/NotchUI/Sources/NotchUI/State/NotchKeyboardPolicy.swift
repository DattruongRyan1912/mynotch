import MyNotchCore

/// When the notch panel takes keyboard focus: only while an open tab asks for it. Toasts never do,
/// so a toast arriving over a search field hands the keyboard back to the app in front.
enum NotchKeyboardPolicy {
    static func wantsKeyboard(state: NotchState, tabs: [NotchTab]) -> Bool {
        guard case .open(let id?) = state else { return false }
        return tabs.first { $0.id == id }?.acceptsKeyboard ?? false
    }
}
