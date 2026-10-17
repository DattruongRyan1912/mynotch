/// Which SMC keys are die temperatures. On this Mac (M1 Pro) the CPU's are `Tp*` (a low, a middle and a high sensor for each
/// of the ten cores) and `Te*`, the GPU's are `Tg*`; the other `T*` keys are aggregates of those, regulators, or the power
/// chip, board, battery and flash, which run 15 to 30 degrees cooler (TH0 report). Matched by prefix, so a Mac with more or
/// fewer sensors needs no list.
public enum SMCSensorCatalog {
    public enum Role: Equatable, Sendable { case cpu, gpu }

    public static func role(of key: String) -> Role? {
        guard key.utf8.count == 4 else { return nil }
        if key.hasPrefix("Tp") || key.hasPrefix("Te") { return .cpu }
        if key.hasPrefix("Tg") { return .gpu }
        return nil
    }

    /// The die sensors among `keys`, each list in the order of `keys`.
    public static func dieSensors(in keys: [String]) -> (cpu: [String], gpu: [String]) {
        (keys.filter { role(of: $0) == .cpu }, keys.filter { role(of: $0) == .gpu })
    }
}

public enum DieTemperature {
    /// A running Mac's die is never colder than the room and never hotter than the chip allows; the SMC reports 0.0 for a sensor
    /// that is not wired up and the odd low number for one that is not a die at all.
    public static let plausible = 10.0...130.0

    /// The hottest of the readings that make sense, or nil when none does.
    public static func hottest(of readings: [Double]) -> Double? {
        readings.filter(plausible.contains).max()
    }
}

/// The die sensors of a Mac found once, read again and again: what the helper's heat guard asks for. Read-only.
public struct DieSensors: Sendable {
    private let keys: [(key: String, info: SMCKeyInfo)]

    /// Walks the SMC's key list once. Nil when there is no die sensor to read.
    public init?(channel: any SMCChannel) {
        guard let info = channel.info(of: "#KEY"), let bytes = channel.bytes(of: "#KEY", info: info),
              let count = SMCValue.number(type: info.type, bytes: bytes)
        else { return nil }
        let names = (0..<Int(count)).compactMap(channel.keyName(at:))
        let found = SMCSensorCatalog.dieSensors(in: names.filter { SMCSensorCatalog.role(of: $0) != nil })
        let usable = (found.cpu + found.gpu).compactMap { key -> (String, SMCKeyInfo)? in
            guard let info = channel.info(of: key), info.type == "flt ", info.size == 4 else { return nil }
            return (key, info)
        }
        guard !usable.isEmpty else { return nil }
        keys = usable
    }

    public func hottest(on channel: any SMCChannel) -> Double? {
        DieTemperature.hottest(of: keys.compactMap { entry in
            channel.bytes(of: entry.key, info: entry.info).flatMap { SMCValue.number(type: entry.info.type, bytes: $0) }
        })
    }
}
