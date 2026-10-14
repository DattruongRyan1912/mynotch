import MyNotchCore

/// App-wide settings (`app.*`).
enum AppSettings {
    static let showMenuBarIcon = SettingKey("app.showMenuBarIcon", default: true)
    /// Fingerprint of the code-signing identity the last launch ran with ("" before the first launch). macOS forgets
    /// every permission when it changes, so a different one opens the Permissions page.
    static let permissionIdentity = SettingKey("app.permissionIdentity", default: "")
}
