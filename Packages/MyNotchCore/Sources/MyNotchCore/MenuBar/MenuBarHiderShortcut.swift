/// The global shortcut that shows and hides the menu-bar icons. It has no default key, so it can clash with nothing the user
/// did not choose; the user sets it in Settings, which lists clashing keys.
public enum MenuBarHiderShortcut {
    /// Fixed: it is the key the user's recorded combination is stored under, so renaming it would drop their choice.
    public static let name = "toggleMenuBarIcons"
    public static let title = "Hiện/ẩn icon menu bar"

    public static func register(in registry: HotkeyRegistry, toggle: @escaping @MainActor () -> Void) {
        registry.register(name, title: title, owner: nil, action: toggle)
    }
}
