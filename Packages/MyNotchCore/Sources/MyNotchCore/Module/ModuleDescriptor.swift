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
    public let order: Int

    public init(
        id: ModuleID,
        displayName: String,
        systemImage: String,
        defaultEnabled: Bool,
        permissions: [Permission] = [],
        optionalPermissions: [Permission] = [],
        order: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
        self.defaultEnabled = defaultEnabled
        self.permissions = permissions
        self.optionalPermissions = optionalPermissions
        self.order = order
    }
}
