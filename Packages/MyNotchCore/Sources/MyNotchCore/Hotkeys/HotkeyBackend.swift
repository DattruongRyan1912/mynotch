import KeyboardShortcuts

/// The global-shortcut calls `HotkeyRegistry` makes: KeyboardShortcuts in the app, an in-memory fake in tests,
/// so tests neither take key combinations from the system nor store shortcuts in the user's defaults.
public protocol HotkeyBackend: AnyObject {
    /// The name to register under, with `initial` assigned unless a shortcut was already stored for `rawValue`.
    func makeName(_ rawValue: String, initial: KeyboardShortcuts.Shortcut?) -> KeyboardShortcuts.Name
    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void)
    func removeHandler(for name: KeyboardShortcuts.Name)
    func getShortcut(for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut?
}

/// The app's backend: system-wide shortcuts that KeyboardShortcuts stores in the standard user defaults.
public final class KeyboardShortcutsBackend: HotkeyBackend {
    public init() {}

    public func makeName(_ rawValue: String, initial: KeyboardShortcuts.Shortcut?) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name(rawValue, initial: initial)
    }

    public func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: name) { MainActor.assumeIsolated { action() } }
    }

    public func removeHandler(for name: KeyboardShortcuts.Name) {
        KeyboardShortcuts.removeHandler(for: name)
    }

    public func getShortcut(for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name)
    }
}
