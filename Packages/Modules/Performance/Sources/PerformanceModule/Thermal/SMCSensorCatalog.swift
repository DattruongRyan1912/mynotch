/// Which SMC keys are die temperatures. On this Mac (M1 Pro) the CPU's are `Tp*` (a low, a middle and a high sensor for each
/// of the ten cores) and `Te*`, the GPU's are `Tg*`; the other `T*` keys are aggregates of those, regulators, or the power
/// chip, board, battery and flash, which run 15 to 30 degrees cooler (TH0 report). Matched by prefix, so a Mac with more or
/// fewer sensors needs no list.
nonisolated enum SMCSensorCatalog {
    enum Role: Equatable, Sendable { case cpu, gpu }

    static func role(of key: String) -> Role? {
        guard key.utf8.count == 4 else { return nil }
        if key.hasPrefix("Tp") || key.hasPrefix("Te") { return .cpu }
        if key.hasPrefix("Tg") { return .gpu }
        return nil
    }

    /// The die sensors among `keys`, each list in the order of `keys`.
    static func dieSensors(in keys: [String]) -> (cpu: [String], gpu: [String]) {
        (keys.filter { role(of: $0) == .cpu }, keys.filter { role(of: $0) == .gpu })
    }
}
