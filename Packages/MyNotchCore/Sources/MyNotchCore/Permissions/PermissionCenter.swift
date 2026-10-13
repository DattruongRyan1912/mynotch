/// Checks and requests system permissions, and opens System Settings.
public protocol PermissionCenter: AnyObject {
    /// Never prompts, so it is safe to call while rendering or polling.
    func status(of permission: Permission) -> PermissionStatus
    /// Prompts when the system still allows it, then returns the resulting status.
    func request(_ permission: Permission) async -> PermissionStatus
    func openSystemSettings(for permission: Permission)
}
