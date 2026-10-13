import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message when macOS refuses the change.
    static func set(_ enabled: Bool) -> String? {
        do {
            enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
