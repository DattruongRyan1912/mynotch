/// What a module's Settings rows get, whether or not the module is running.
public struct ModuleSettingsEnvironment {
    /// Same namespace as the module's `ModuleContext.settings`, so a running module sees every change.
    public let settings: ModuleSettings
    public let storage: ModuleStorage
    public let permissions: any PermissionCenter
    /// State when the rows were built; the Settings page rebuilds them when it changes.
    public let isRunning: Bool
}
