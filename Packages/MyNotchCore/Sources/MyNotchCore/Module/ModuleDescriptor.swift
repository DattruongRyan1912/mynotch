/// Static facts about a module, shown in Settings and used by the registry.
nonisolated public struct ModuleDescriptor: Sendable {
    public let id: ModuleID
    public let displayName: String
    public let systemImage: String
    public let defaultEnabled: Bool
    /// Required: the module stays in `.needsPermission` until all are granted.
    public let permissions: [Permission]
    /// Shown in Settings with a grant button but never block `start`; the module checks them before use.
    public let optionalPermissions: [Permission]
    /// One line per declared permission on what this module uses it for, in Vietnamese, shown on the Permissions page.
    /// A permission without a line there shows `Permission.summary`.
    public let permissionReasons: [Permission: String]
    public let order: Int

    public init(
        id: ModuleID,
        displayName: String,
        systemImage: String,
        defaultEnabled: Bool,
        permissions: [Permission] = [],
        optionalPermissions: [Permission] = [],
        permissionReasons: [Permission: String] = [:],
        order: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
        self.defaultEnabled = defaultEnabled
        self.permissions = permissions
        self.optionalPermissions = optionalPermissions
        self.permissionReasons = permissionReasons
        self.order = order
    }
}
