import AudioToolbox
import CoreAudio
import Dispatch
import Observation

/// The default output device's volume and whether it is muted.
nonisolated struct VolumeReading: Equatable, Sendable {
    /// 0...1 as the system's own slider has it.
    var level: Float
    var isMuted: Bool
}

/// The default output device, as the volume row needs it. Every call can wait on coreaudiod (a busy one made single calls
/// last hundreds of milliseconds), so they are made on a `VolumeQueue` and nowhere else. A protocol so tests use a fake and
/// never read or change the real one.
nonisolated protocol VolumeHardware: AnyObject, Sendable {
    /// nil when the default output device has no volume that can be set (many HDMI and aggregate devices).
    func read() -> VolumeReading?
    /// False when it did not take.
    func writeLevel(_ level: Float) -> Bool
    /// False when the device has no mute, or it did not take.
    func writeMuted(_ muted: Bool) -> Bool
    /// Listens for a change of the level, the mute or which device is the default, until the observation is stopped.
    /// Called on the queue, and calls `onChange` there.
    func observe(_ onChange: @escaping @Sendable () -> Void) -> any VolumeObservation
}

nonisolated protocol VolumeObservation: AnyObject, Sendable {
    /// Removes the listeners. Called on the queue.
    func stop()
}

/// Where the hardware is called: off the main thread, one piece of work after the other.
nonisolated protocol VolumeQueue: AnyObject, Sendable {
    /// Runs `work` on the queue, then `completion` with its result on the main actor, in the order the work was given.
    func run<T: Sendable>(_ work: @escaping @Sendable () -> T, then completion: @escaping @MainActor (T) -> Void)
}

/// What the volume row shows and sets. Nothing here waits for Core Audio: reads and writes go to the queue, the last known
/// reading shows until the answer comes, and the device is listened to only while a view watches (the slider is open).
@Observable
final class VolumeModel {
    /// The latest reading, or what the slider was last moved to while the device has not answered. nil while unread, and when
    /// the output device has no volume to set.
    private(set) var reading: VolumeReading?

    @ObservationIgnored private let hardware: any VolumeHardware
    @ObservationIgnored private let queue: any VolumeQueue
    /// The latest slider position not written yet. Samples of a drag replace one another here.
    @ObservationIgnored private var pending: Float?
    @ObservationIgnored private var isWriting = false
    @ObservationIgnored private var observation: ObservationSlot?

    init(hardware: any VolumeHardware, queue: any VolumeQueue) {
        self.hardware = hardware
        self.queue = queue
    }

    /// The real output device, on a serial queue of its own.
    static func system() -> VolumeModel {
        let queue = DispatchQueue(label: "io.lucasvu.mynotch.media.volume", qos: .userInitiated)
        return VolumeModel(hardware: CoreAudioHardware(queue: queue), queue: SerialVolumeQueue(queue: queue))
    }

    isolated deinit { stopWatching() }

    var level: Float? { reading?.level }
    var isMuted: Bool { reading?.isMuted ?? false }
    var isAvailable: Bool { reading != nil }

    /// The level as a whole percent, nil while there is none.
    var percent: Int? { level.map { Int(($0 * 100).rounded()) } }

    /// The speaker of the slider.
    var symbol: String { isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill" }

    /// Asks the device; the answer arrives later.
    func refresh() {
        let hardware = hardware
        queue.run({ hardware.read() }, then: { [weak self] in self?.received($0) })
    }

    /// Moves the volume to where the slider is, kept between silence and full, and unmutes it, as the system's volume keys
    /// do. The slider shows the position at once. A drag gives many positions: one write is in flight at a time and the
    /// latest position follows it. A write the device does not take shows as what the device reads after it.
    func set(_ requested: Float) {
        guard let current = reading, requested.isFinite else { return }
        let target = min(max(requested, 0), 1)
        let unmutes = current.isMuted && target > 0
        guard target != (pending ?? current.level) || unmutes else { return }
        reading = VolumeReading(level: target, isMuted: current.isMuted && !unmutes)
        pending = target
        flush()
    }

    func startWatching() {
        stopWatching()
        let slot = ObservationSlot()
        observation = slot
        let hardware = hardware
        let queue = queue
        let apply: @MainActor (VolumeReading?) -> Void = { [weak self] in self?.received($0) }
        queue.run({ slot.current = hardware.observe { queue.run({ hardware.read() }, then: apply) } }, then: { _ in })
        refresh()
    }

    /// The stop is queued behind the start, so it finds what the start made.
    func stopWatching() {
        guard let slot = observation else { return }
        observation = nil
        queue.run({
            slot.current?.stop()
            slot.current = nil
        }, then: { _ in })
    }

    private func flush() {
        guard !isWriting, let target = pending else { return }
        pending = nil
        isWriting = true
        let hardware = hardware
        queue.run({ Self.write(target, to: hardware) }, then: { [weak self] in self?.wrote($0) })
    }

    private func wrote(_ result: VolumeReading?) {
        isWriting = false
        if pending != nil { flush() } else { apply(result) }
    }

    /// A read taken before a write that is in flight or waiting is older than it: the write's answer follows.
    private func received(_ read: VolumeReading?) {
        guard !isWriting, pending == nil else { return }
        apply(read)
    }

    private func apply(_ new: VolumeReading?) {
        if new != reading { reading = new }
    }

    /// Writes the level, unmutes when it is a sound that was muted, and answers with what the device reads afterwards.
    nonisolated private static func write(_ level: Float, to hardware: any VolumeHardware) -> VolumeReading? {
        guard let before = hardware.read() else { return nil }
        _ = hardware.writeLevel(level)
        if before.isMuted, level > 0 { _ = hardware.writeMuted(false) }
        return hardware.read()
    }
}

/// Where the queue puts the observation it started, so that stopping needs no answer from the start: the stop runs behind
/// it on the same queue, which is the only place this is touched.
private nonisolated final class ObservationSlot: @unchecked Sendable {
    var current: (any VolumeObservation)?
}

/// The queue of the real device: one serial dispatch queue, with the results back on the main queue, which keeps them in
/// the order the work was given.
nonisolated final class SerialVolumeQueue: VolumeQueue {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(label: "io.lucasvu.mynotch.media.volume", qos: .userInitiated)) {
        self.queue = queue
    }

    func run<T: Sendable>(_ work: @escaping @Sendable () -> T, then completion: @escaping @MainActor (T) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(result) } }
        }
    }
}

/// The hardware of a build that cannot reach the system's volume, which is what tests get unless they bring a fake.
nonisolated final class NoVolumeHardware: VolumeHardware {
    init() {}

    func read() -> VolumeReading? { nil }
    func writeLevel(_ level: Float) -> Bool { false }
    func writeMuted(_ muted: Bool) -> Bool { false }
    func observe(_ onChange: @escaping @Sendable () -> Void) -> any VolumeObservation { NoObservation() }

    private final class NoObservation: VolumeObservation {
        func stop() {}
    }
}

/// The default output device's main volume and mute through public Core Audio, which are what the volume keys and the menu
/// bar slider change too. Nothing is cached: the default device can change at any moment.
nonisolated final class CoreAudioHardware: VolumeHardware {
    /// The queue the model uses, which the listeners are delivered on too.
    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func read() -> VolumeReading? {
        guard let device = CoreAudioProperties.settableVolumeDevice(),
              let level = CoreAudioProperties.read(Float32.self, device, CoreAudioProperties.volume) else { return nil }
        let isMuted = CoreAudioProperties.muteAddresses(of: device).first
            .flatMap { CoreAudioProperties.read(UInt32.self, device, $0) }.map { $0 != 0 } ?? false
        return VolumeReading(level: min(max(level, 0), 1), isMuted: isMuted)
    }

    func writeLevel(_ level: Float) -> Bool {
        guard let device = CoreAudioProperties.settableVolumeDevice() else { return false }
        return CoreAudioProperties.write(Float32(min(max(level, 0), 1)), device, CoreAudioProperties.volume)
    }

    func writeMuted(_ muted: Bool) -> Bool {
        guard let device = CoreAudioProperties.defaultDeviceID() else { return false }
        let addresses = CoreAudioProperties.muteAddresses(of: device)
        guard !addresses.isEmpty else { return false }
        let value: UInt32 = muted ? 1 : 0
        return addresses.map { CoreAudioProperties.write(value, device, $0) }.allSatisfy { $0 }
    }

    func observe(_ onChange: @escaping @Sendable () -> Void) -> any VolumeObservation {
        CoreAudioVolumeObservation(queue: queue, onChange: onChange)
    }
}

/// The default output device and its volume and mute properties, shared by what reads and sets them and what listens to them.
private nonisolated enum CoreAudioProperties {
    static let defaultDevice = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    static let volume = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// nil when there is no default output device.
    static func defaultDeviceID() -> AudioObjectID? {
        var address = defaultDevice
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// The default output device when its volume can be set.
    static func settableVolumeDevice() -> AudioObjectID? {
        guard let device = defaultDeviceID(), has(device, volume), isSettable(device, volume) else { return nil }
        return device
    }

    /// The device's mute: the main one, or for a device that exposes mute only per channel, the left and right ones.
    /// Empty when it has none.
    static func muteAddresses(of device: AudioObjectID) -> [AudioObjectPropertyAddress] {
        let main = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if has(device, main) { return [main] }
        return [1, 2].map {
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: $0)
        }.filter { has(device, $0) }
    }

    static func has(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(device, &address)
    }

    static func isSettable(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static func read<T: Numeric & BitwiseCopyable>(_ type: T.Type, _ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func write<T: Numeric & BitwiseCopyable>(_ value: T, _ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }
}

/// Listens to the default output device's volume and mute and re-binds when another device becomes the default. Everything
/// here, the listeners' deliveries included, runs on `queue`: the observation is started and stopped there.
private nonisolated final class CoreAudioVolumeObservation: VolumeObservation, @unchecked Sendable {
    /// Typed as the block the API takes, and the same value is given to add and to remove: Core Audio finds a listener to
    /// remove by that block, and a Swift closure bridges to a new block at every call, which it would never find.
    private typealias Listener = (object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)

    private let queue: DispatchQueue
    private var onChange: (@Sendable () -> Void)?
    private var systemListener: Listener?
    private var deviceListeners: [Listener] = []

    init(queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.onChange = onChange
        systemListener = add(AudioObjectID(kAudioObjectSystemObject), CoreAudioProperties.defaultDevice) { [weak self] in
            self?.bind()
            self?.onChange?()
        }
        bind()
    }

    func stop() {
        ([systemListener].compactMap { $0 } + deviceListeners).forEach(remove)
        systemListener = nil
        deviceListeners = []
        onChange = nil
    }

    private func bind() {
        deviceListeners.forEach(remove)
        deviceListeners = []
        guard let device = CoreAudioProperties.defaultDeviceID(), CoreAudioProperties.has(device, CoreAudioProperties.volume) else { return }
        for address in [CoreAudioProperties.volume] + CoreAudioProperties.muteAddresses(of: device).prefix(1) {
            if let listener = add(device, address, { [weak self] in self?.onChange?() }) { deviceListeners.append(listener) }
        }
    }

    private func add(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ action: @escaping @Sendable () -> Void) -> Listener? {
        let block: AudioObjectPropertyListenerBlock = { _, _ in action() }
        var address = address
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else { return nil }
        return (object, address, block)
    }

    private func remove(_ listener: Listener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(listener.object, &address, queue, listener.block)
    }
}
