/// What a press of the MyNotch menu-bar icon does while the hider is on, and what its tooltip says.
nonisolated public enum MenuBarIcon {
    nonisolated public enum Action: Equatable, Sendable {
        /// Opens or closes the bar under the menu bar that holds the hidden icons.
        case toggleBar
        case toggleHiddenIcons
        /// An ⌥-click: the always-hidden zone too.
        case toggleAllIcons
        case openMenu
    }

    /// An event older than this was not what made the button send its action.
    public static let maxEventAge = 0.5

    /// Only a left mouse click on the icon toggles. Anything else opens the menu: a right or control click, and every activation
    /// that is no click at all (keyboard, VoiceOver), whose "current event" is a key, something stale or nothing, so the menu stays
    /// reachable without a mouse. A plain click opens the bar when it is to take the place of showing the hidden icons in the menu
    /// bar; ⌥ keeps showing them in place (with ‹‹, the always-hidden zone too), as it did before the bar.
    public static func action(
        isLeftMouseUp: Bool, hasControl: Bool, hasOption: Bool = false, eventAge: Double, isOnButton: Bool,
        barInsteadOfExpanding: Bool = false
    ) -> Action {
        guard isLeftMouseUp, !hasControl, eventAge < maxEventAge, isOnButton else { return .openMenu }
        return separatorAction(hasOption: hasOption, barInsteadOfExpanding: barInsteadOfExpanding)
    }

    /// A click on ‹ does what a click on the icon does.
    public static func separatorAction(hasOption: Bool, barInsteadOfExpanding: Bool) -> Action {
        if hasOption { return .toggleAllIcons }
        return barInsteadOfExpanding ? .toggleBar : .toggleHiddenIcons
    }

    /// The permission nudge, when there is one, and the line that explains the clicks while the hider is on.
    public static func toolTip(
        permissionNudge: String?, hiderIsOn: Bool, alwaysHiddenSection: Bool = false, barInsteadOfExpanding: Bool = false
    ) -> String? {
        let clicks = switch (barInsteadOfExpanding, alwaysHiddenSection) {
        case (true, true): "Bấm: mở thanh icon ẩn. Giữ ⌥ khi bấm: hiện icon ngay trên menu bar, cả icon luôn ẩn. Chuột phải: menu."
        case (true, false): "Bấm: mở thanh icon ẩn. Giữ ⌥ khi bấm: hiện icon ngay trên menu bar. Chuột phải: menu."
        case (false, true): "Bấm: hiện/ẩn icon. Giữ ⌥ khi bấm: cả icon luôn ẩn. Chuột phải: menu."
        case (false, false): "Bấm: hiện/ẩn icon. Chuột phải: menu."
        }
        let lines = [permissionNudge.map { "MyNotch: \($0)" }, hiderIsOn ? clicks : nil]
        let text = lines.compactMap { $0 }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
