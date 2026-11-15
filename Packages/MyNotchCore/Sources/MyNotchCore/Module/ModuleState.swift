/// Lifecycle state of a module, owned by `ModuleRegistry`.
nonisolated public enum ModuleState: Equatable, Sendable {
    case disabled
    case starting
    case running
    case stopping
    case needsPermission(Permission)
    case unavailable(reason: String)
    case failed(reason: String)

    init(_ error: ModuleError) {
        switch error {
        case .needsPermission(let permission): self = .needsPermission(permission)
        case .unavailable(let reason): self = .unavailable(reason: reason)
        case .failed(let reason): self = .failed(reason: reason)
        }
    }
}
