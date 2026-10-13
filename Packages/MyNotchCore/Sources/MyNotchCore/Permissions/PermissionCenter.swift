/// Checks permission status without prompting, and opens System Settings.
public protocol PermissionCenter: AnyObject {
    func status(of permission: Permission) -> PermissionStatus
    func openSystemSettings(for permission: Permission)
}
