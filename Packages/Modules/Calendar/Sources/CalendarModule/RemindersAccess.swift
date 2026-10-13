import MyNotchCore

/// Asking for Reminders access, shared by the tab's button and the Settings row.
struct RemindersAccess {
    let permissions: any PermissionCenter

    /// Prompts only while the user hasn't answered; after a "no" only System Settings can change it, so with
    /// `openSettingsIfDenied` (an explicit click on a button, not a toggle) that is where the user is sent.
    @discardableResult
    func request(openSettingsIfDenied: Bool) async -> PermissionStatus {
        let before = permissions.status(of: .reminders)
        guard before != .granted else { return .granted }
        let after = await permissions.request(.reminders)
        if openSettingsIfDenied, before != .notDetermined, after != .granted {
            permissions.openSystemSettings(for: .reminders)
        }
        return after
    }
}
