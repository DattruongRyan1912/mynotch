import CoreAudio
import EqualizerDSP
import Foundation

/// Everything `PipelineManager` needs from Core Audio, so tests can stand a script in for the machine.
nonisolated public protocol AudioSystem: Sendable {
    /// MyNotch's own process object, or nil while it has none (it has one only once it has audio running).
    var ownProcessID: AudioObjectID? { get }
    /// UID of every output device that a process **other than MyNotch** is playing to, by each process's own device list and `isRunningOutput`.
    func activeOutputDeviceUIDs() -> Set<String>
    func deviceName(uid: String) -> String?
    /// Builds a tap, an aggregate device and an IO proc on one device, and starts them. All or nothing: a step that fails
    /// leaves nothing of the earlier ones behind.
    func makePipeline(deviceUID: String, chain: EQChain) throws -> any PipelineHandle
    /// Calls `handler` on the **main thread** whenever the set of playing processes or devices, or a device's sample rate, may have
    /// changed. Bursts are normal and the handler may be called with nothing new. Dropping the token stops it.
    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject
}

/// One running pipeline on one device.
nonisolated public protocol PipelineHandle: AnyObject, Sendable {
    /// The sample rate of the audio the pipeline is filtering **now**: it follows the tap's format, so a change on the device shows.
    var sampleRate: Double { get }
    /// The loudest sample the tap delivered since the last call (0 when there was none). Exact zeros are what a denied tap hears.
    func takePeak() -> Float
    /// Stops and destroys everything the pipeline made. Safe to call twice.
    func tearDown()
}

nonisolated struct AudioSystemError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

/// What the manager needs to know about one process that is connected to Core Audio.
nonisolated struct ProcessOutput: Equatable, Sendable {
    var pid: pid_t
    var isRunningOutput: Bool
    var deviceUIDs: [String]
}

nonisolated enum ActiveDevices {
    /// The devices some process other than `own` is playing to. MyNotch is left out by process id, not by a remembered object:
    /// its replay runs on the very device it filters, so counting it would keep that device "playing" for ever.
    static func uids(in processes: [ProcessOutput], excludingPID own: pid_t) -> Set<String> {
        var uids = Set<String>()
        for process in processes where process.pid != own && process.isRunningOutput {
            uids.formUnion(process.deviceUIDs)
        }
        return uids
    }
}

/// The real thing, on `AudioHardwareSystem`. Only this touches Core Audio; tests use a fake.
public struct CoreAudioSystem: AudioSystem {
    public init() {}

    public var ownProcessID: AudioObjectID? { Self.ownProcessID() }

    static func ownProcessID(_ hardware: AudioHardwareSystem = .shared) -> AudioObjectID? {
        (try? hardware.process(for: getpid()))?.id
    }

    public func activeOutputDeviceUIDs() -> Set<String> {
        let own = getpid()
        guard let processes = try? AudioHardwareSystem.shared.processes else { return [] }
        var snapshots: [ProcessOutput] = []
        for process in processes {
            guard let pid = try? process.pid else { continue }
            // Reading a process's devices is a round trip to coreaudiod: only for the ones that play.
            let isPlaying = pid != own && ((try? process.isRunningOutput) ?? false)
            snapshots.append(ProcessOutput(pid: pid, isRunningOutput: isPlaying, deviceUIDs: isPlaying ? Self.outputDeviceUIDs(of: process) : []))
        }
        return ActiveDevices.uids(in: snapshots, excludingPID: own)
    }

    /// Asks for the output scope by name: the header says the scope picks which list comes back, and the Swift `devices`
    /// property does not say which one it picks.
    private static func outputDeviceUIDs(of process: AudioHardwareProcess) -> [String] {
        let address = PropertyAddress(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
        guard let data = try? process.propertyData(address: address) else { return [] }
        let ids = data.withUnsafeBytes { Array($0.bindMemory(to: AudioObjectID.self)) }
        return ids.compactMap { try? AudioHardwareDevice(id: $0).uid }
    }

    public func deviceName(uid: String) -> String? {
        guard let device = try? AudioHardwareSystem.shared.device(forUID: uid) else { return nil }
        return try? device.name
    }

    public func makePipeline(deviceUID: String, chain: EQChain) throws -> any PipelineHandle {
        try DevicePipeline.make(deviceUID: deviceUID, chain: chain)
    }

    public func observeChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        let observation = ChangeObservation { DispatchQueue.main.async(execute: handler) }
        observation.start()
        return observation
    }
}
