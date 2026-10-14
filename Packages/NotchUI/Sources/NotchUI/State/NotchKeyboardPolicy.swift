import MyNotchCore

/// When the notch panel takes the keyboard. A tab that accepts it keeps it under a toast, so a toast never hands
/// typing back to the app in front halfway through a search.
enum NotchKeyboardPolicy {
    /// The panel may become key: the shown tab (open, or covered by a toast) accepts keyboard input.
    /// Clicking into a keyboard tab therefore makes the panel key even when hovering opened it.
    static func wantsKeyboard(state: NotchState, tabUnderToast: ModuleID?, tabs: [NotchTab]) -> Bool {
        guard let id = state.shownTab(tabUnderToast: tabUnderToast) else { return false }
        return tabs.first { $0.id == id }?.acceptsKeyboard ?? false
    }

    /// The panel takes the keyboard by itself only when the notch was opened on purpose (click, shortcut, tab bar,
    /// a module); hovering past the notch must not steal typing from the app in front.
    static func focusesKeyboard(state: NotchState, tabUnderToast: ModuleID?, tabs: [NotchTab], onPurpose: Bool) -> Bool {
        onPurpose && wantsKeyboard(state: state, tabUnderToast: tabUnderToast, tabs: tabs)
    }

    /// What the window controller does with the panel's key status after the shown tab or the notch changed.
    struct PanelKeyPlan: Equatable {
        /// Value for `NotchPanel.allowsKeyStatus`.
        var allowsKeyStatus: Bool
        /// The panel takes the keyboard now (focus just started being wanted).
        var makeKey: Bool
        /// Give key status back to the app in front.
        var handBack: Bool
    }

    /// The panel is key and the shown tab no longer wants the keyboard (a tab switch, a close): key status goes back to the
    /// app in front at once, in place (`KeyboardReturn`), so the notch never has to leave the screen for it.
    static func panelKeyPlan(wants: Bool, focuses: Bool, wasFocused: Bool, isKey: Bool, isVisible: Bool) -> PanelKeyPlan {
        PanelKeyPlan(
            allowsKeyStatus: wants,
            // An ordered-out panel must not take the keyboard where nobody can see it.
            makeKey: focuses && !wasFocused && isVisible,
            handBack: !wants && isKey && isVisible
        )
    }
}
