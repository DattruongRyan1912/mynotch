/// Static facts about a module, shown in Settings and used by the registry.
nonisolated public struct ModuleDescriptor: Sendable {
    public let id: ModuleID
    public let displayName: String
    public let systemImage: String
    public let defaultEnabled: Bool
    public let permissions: [Permission]
    public let order: Int

    public init(
        id: ModuleID,
        displayName: String,
        systemImage: String,
        defaultEnabled: Bool,
        permissions: [Permission] = [],
        order: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
        self.defaultEnabled = defaultEnabled
        self.permissions = permissions
        self.order = order
    }
}
