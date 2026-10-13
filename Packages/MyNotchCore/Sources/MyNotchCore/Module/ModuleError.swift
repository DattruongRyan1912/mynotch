/// The only errors a module may report. The registry maps them to `ModuleState`.
nonisolated public enum ModuleError: Error, Sendable, Equatable {
    case needsPermission(Permission)
    case unavailable(reason: String)
    case failed(reason: String)
}
