/// What a press of the MyNotch menu-bar icon does while the hider is on, and what its tooltip says.
nonisolated public enum MenuBarIcon {
    nonisolated public enum Action: Equatable, Sendable {
        case toggleHiddenIcons
        /// An ⌥-click: the always-hidden zone too.
        case toggleAllIcons
        case openMenu
    }

    /// An event older than this was not what made the button send its action.
    public static let maxEventAge = 0.5

    /// Only a left mouse click on the icon toggles, with ⌥ the always-hidden zone too. Anything else opens the menu: a right or
    /// control click, and every activation that is no click at all (keyboard, VoiceOver), whose "current event" is a key,
    /// something stale or nothing, so the menu stays reachable without a mouse.
    public static func action(
        isLeftMouseUp: Bool, hasControl: Bool, hasOption: Bool = false, eventAge: Double, isOnButton: Bool
    ) -> Action {
        guard isLeftMouseUp, !hasControl, eventAge < maxEventAge, isOnButton else { return .openMenu }
        return hasOption ? .toggleAllIcons : .toggleHiddenIcons
    }

    /// The permission nudge, when there is one, and the line that explains the clicks while the hider is on.
    public static func toolTip(permissionNudge: String?, hiderIsOn: Bool, alwaysHiddenSection: Bool = false) -> String? {
        let clicks = alwaysHiddenSection
            ? "Bấm: hiện/ẩn icon. Giữ ⌥ khi bấm: cả icon luôn ẩn. Chuột phải: menu."
            : "Bấm: hiện/ẩn icon. Chuột phải: menu."
        let lines = [permissionNudge.map { "MyNotch: \($0)" }, hiderIsOn ? clicks : nil]
        let text = lines.compactMap { $0 }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
