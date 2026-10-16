/// Reads the Mac's temperatures and fan speeds; faked in tests. Whatever it does is off the main actor.
nonisolated protocol ThermalReading: Sendable {
    /// Whether the SMC can be opened at all. Cheap: the sensors are found by the first `read`, which takes a while.
    func isAvailable() async -> Bool
    /// Nil when there is nothing to read.
    func read() async -> ThermalSnapshot?
    /// Lets go of the connection to the SMC; the next call opens it again.
    func shutdown() async
}

/// Reads through the SMC, read-only. The first `read` finds the sensors (the CPU and GPU die keys by prefix, the fans from
/// `FNum`, and each fan's limits), which means walking the list of all the SMC's keys once, about a thousand requests; after
/// that a read is one request per sensor and per fan. An actor, so the blocking calls never run on the main actor and never
/// overlap.
actor SMCThermalReader: ThermalReading {
    private struct Sensor {
        let key: String
        let info: SMCKeyInfo
    }

    private struct Fan {
        let index: Int
        let key: String
        let info: SMCKeyInfo
        let minRPM: Double
        let maxRPM: Double
    }

    /// What was found; kept even when empty, so a Mac with nothing to show is not searched again at every read.
    private struct Plan {
        let cpu: [Sensor]
        let gpu: [Sensor]
        let fans: [Fan]

        var isEmpty: Bool { cpu.isEmpty && gpu.isEmpty && fans.isEmpty }
    }

    private let openChannel: @Sendable () -> (any SMCChannel)?
    private var channel: (any SMCChannel)?
    private var plan: Plan?

    init(openChannel: @escaping @Sendable () -> (any SMCChannel)? = { AppleSMCChannel() }) {
        self.openChannel = openChannel
    }

    func isAvailable() -> Bool {
        connect() != nil
    }

    func read() -> ThermalSnapshot? {
        guard let channel = connect() else { return nil }
        let plan = self.plan ?? Self.discover(on: channel)
        self.plan = plan
        guard !plan.isEmpty else { return nil }
        let fans = plan.fans.compactMap { fan -> FanReading? in
            guard let rpm = Self.number(fan.key, fan.info, on: channel) else { return nil }
            return FanReading(index: fan.index, rpm: rpm, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
        }
        return ThermalSnapshot(
            cpu: DieTemperature.hottest(of: plan.cpu.compactMap { Self.number($0.key, $0.info, on: channel) }),
            gpu: DieTemperature.hottest(of: plan.gpu.compactMap { Self.number($0.key, $0.info, on: channel) }),
            fans: fans
        )
    }

    func shutdown() {
        channel = nil
        plan = nil
    }

    /// The open connection, opened now if it is not; nil when the SMC cannot be opened.
    private func connect() -> (any SMCChannel)? {
        if channel == nil { channel = openChannel() }
        return channel
    }

    private static func number(_ key: String, _ info: SMCKeyInfo, on channel: any SMCChannel) -> Double? {
        channel.bytes(of: key, info: info).flatMap { SMCValue.number(type: info.type, bytes: $0) }
    }

    private static func discover(on channel: any SMCChannel) -> Plan {
        let names = (0..<keyCount(on: channel)).compactMap(channel.keyName(at:))
        let found = SMCSensorCatalog.dieSensors(in: names)
        return Plan(cpu: sensors(found.cpu, on: channel), gpu: sensors(found.gpu, on: channel), fans: fans(on: channel))
    }

    private static func keyCount(on channel: any SMCChannel) -> Int {
        guard let info = channel.info(of: "#KEY"), let count = number("#KEY", info, on: channel) else { return 0 }
        return Int(count)
    }

    /// Die keys are floats; one of another type (an `ioft` that starts with `Tg`, say) cannot be read and is left out.
    private static func sensors(_ keys: [String], on channel: any SMCChannel) -> [Sensor] {
        keys.compactMap { key in
            guard let info = channel.info(of: key), info.type == "flt ", info.size == 4 else { return nil }
            return Sensor(key: key, info: info)
        }
    }

    /// A fan is shown with its limits, read once here; one without them is left out.
    private static func fans(on channel: any SMCChannel) -> [Fan] {
        guard let info = channel.info(of: "FNum"), let count = number("FNum", info, on: channel) else { return [] }
        return (0..<Int(count)).compactMap { index in
            let keys = ["F\(index)Ac", "F\(index)Mn", "F\(index)Mx"]
            let infos = keys.compactMap { channel.info(of: $0) }
            guard infos.count == 3, infos.allSatisfy({ $0.type == "flt " }),
                  let minRPM = number(keys[1], infos[1], on: channel), let maxRPM = number(keys[2], infos[2], on: channel)
            else { return nil }
            return Fan(index: index, key: keys[0], info: infos[0], minRPM: minRPM, maxRPM: maxRPM)
        }
    }
}
