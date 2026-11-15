import AudioToolbox
import CoreAudio
import EqualizerDSP
import Foundation

/// Everything `PipelineManager` needs from Core Audio, so tests can stand a script in for the machine.
nonisolated public protocol AudioSystem: Sendable {
    /// MyNotch's own process object, or nil while it has none (it has one only once it has audio running).
    var ownProcessID: AudioObjectID? { get }
    /// All processes currently known to Core Audio, with their playing state and device UIDs.
    func activeProcesses() -> [ProcessOutput]
    /// UID of every output device that a process **other than MyNotch** is playing to, by each process's own device list and `isRunningOutput`.
    func activeOutputDeviceUIDs() -> Set<String>
    func deviceName(uid: String) -> String?
    /// Builds a tap, an aggregate device and an IO proc on one device, and starts them. All or nothing: a step that fails
    /// leaves nothing of the earlier ones behind.
    func makePipeline(deviceUID: String, chain: EQChain) throws -> any PipelineHandle
    /// The device's own volume, 0...1, or nil when it has none (HDMI, many USB DACs) or is gone. Read from the device itself, never
    /// from the aggregate device a pipeline makes on it.
    func outputVolume(uid: String) -> Double?
    /// Calls `handler` on the **main thread** whenever the set of playing processes or devices, or a device's sample rate, may have
    /// changed, and `volumeChanged` (also on the main thread) whenever some device's volume did. Bursts are normal and either
    /// may be called with nothing new. Dropping the token stops both.
    func observeChanges(_ handler: @escaping @Sendable () -> Void, volumeChanged: @escaping @Sendable () -> Void) -> AnyObject
}

/// One running pipeline on one device.
nonisolated public protocol PipelineHandle: AnyObject, Sendable {
    /// The sample rate of the audio the pipeline is filtering **now**: it follows the tap's format, so a change on the device shows.
    var sampleRate: Double { get }
    /// The stream channel count of the active device / tap.
    var channelCount: Int { get }
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
nonisolated public struct ProcessOutput: Equatable, Sendable {
    public var pid: pid_t
    public var isRunningOutput: Bool
    public var deviceUIDs: [String]

    public init(pid: pid_t, isRunningOutput: Bool, deviceUIDs: [String] = []) {
        self.pid = pid
        self.isRunningOutput = isRunningOutput
        self.deviceUIDs = deviceUIDs
    }
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

    public func activeProcesses() -> [ProcessOutput] {
        let own = getpid()
        guard let processes = try? AudioHardwareSystem.shared.processes else { return [] }
        var snapshots: [ProcessOutput] = []
        for process in processes {
            guard let pid = try? process.pid else { continue }
            // Reading a process's devices is a round trip to coreaudiod: only for the ones that play.
            let isPlaying = pid != own && ((try? process.isRunningOutput) ?? false)
            snapshots.append(ProcessOutput(pid: pid, isRunningOutput: isPlaying, deviceUIDs: isPlaying ? Self.outputDeviceUIDs(of: process) : []))
        }
        return snapshots
    }

    public func activeOutputDeviceUIDs() -> Set<String> {
        let own = getpid()
        let snapshots = activeProcesses()
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

    public func outputVolume(uid: String) -> Double? {
        guard let device = try? AudioHardwareSystem.shared.device(forUID: uid) else { return nil }
        return OutputVolume.read(device.id)
    }

    public func makePipeline(deviceUID: String, chain: EQChain) throws -> any PipelineHandle {
        try DevicePipeline.make(deviceUID: deviceUID, chain: chain)
    }

    public func observeChanges(_ handler: @escaping @Sendable () -> Void, volumeChanged: @escaping @Sendable () -> Void) -> AnyObject {
        let observation = ChangeObservation(
            deliver: { DispatchQueue.main.async(execute: handler) },
            volumeChanged: { DispatchQueue.main.async(execute: volumeChanged) }
        )
        observation.start()
        return observation
    }
}

/// A device's volume as the volume keys see it: `VirtualMainVolume` stands for the main element, or for the left and right channels
/// of a device that has volume only per channel.
nonisolated enum OutputVolume {
    static let address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static func read(_ device: AudioObjectID) -> Double? {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, value.isFinite else { return nil }
        return min(max(Double(value), 0), 1)
    }
}
