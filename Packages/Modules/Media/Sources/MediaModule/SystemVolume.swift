import AudioToolbox
import CoreAudio
import Observation

/// The default output device's volume. A protocol so tests use a fake and never read or change the real one.
protocol VolumeDevice: AnyObject {
    /// 0...1 as the system's own slider has it; nil when the default output device has no volume that can be set (many HDMI
    /// and aggregate devices).
    func level() -> Float?
    /// False when it did not take.
    func setLevel(_ level: Float) -> Bool
    /// Calls `onChange` whenever the level or which device is the default changes, until the returned closure is called.
    func observe(_ onChange: @escaping @MainActor () -> Void) -> () -> Void
}

/// What the volume row shows and sets. Nothing is read until a view asks, and the device is listened to only while a
/// view watches (the slider is open).
@Observable
final class VolumeModel {
    /// nil while unread, and when the output device has no volume to set.
    private(set) var level: Float?

    @ObservationIgnored private let device: any VolumeDevice
    @ObservationIgnored private var stopObserving: (() -> Void)?

    init(device: any VolumeDevice) {
        self.device = device
    }

    isolated deinit { stopWatching() }

    var isAvailable: Bool { level != nil }

    /// The level as a whole percent, nil while there is none.
    var percent: Int? { level.map { Int(($0 * 100).rounded()) } }

    func refresh() {
        let current = device.level()
        if current != level { level = current }
    }

    /// Writes the level the slider is at, kept between silence and full. A drag reports the same position many times, and a
    /// device that does not take it is read again, so that the slider shows what the volume is.
    func set(_ requested: Float) {
        guard level != nil, requested.isFinite else { return }
        let target = min(max(requested, 0), 1)
        guard target != level else { return }
        if device.setLevel(target) { level = target } else { refresh() }
    }

    func startWatching() {
        stopWatching()
        stopObserving = device.observe { [weak self] in self?.refresh() }
        refresh()
    }

    func stopWatching() {
        stopObserving?()
        stopObserving = nil
    }
}

/// The device of a build that cannot reach the system's volume, which is what tests get unless they bring a fake.
final class NoVolumeDevice: VolumeDevice {
    init() {}

    func level() -> Float? { nil }
    func setLevel(_ level: Float) -> Bool { false }
    func observe(_ onChange: @escaping @MainActor () -> Void) -> () -> Void { {} }
}

/// The default output device's main volume through public Core Audio, which is what the volume keys and the menu bar slider
/// change too. Nothing is cached: the default device can change at any moment.
final class CoreAudioVolume: VolumeDevice {
    init() {}

    func level() -> Float? {
        guard let device = CoreAudioProperties.settableVolumeDevice() else { return nil }
        return CoreAudioProperties.read(Float32.self, device, CoreAudioProperties.volume).map { min(max($0, 0), 1) }
    }

    func setLevel(_ level: Float) -> Bool {
        guard let device = CoreAudioProperties.settableVolumeDevice() else { return false }
        return CoreAudioProperties.write(Float32(min(max(level, 0), 1)), device, CoreAudioProperties.volume)
    }

    func observe(_ onChange: @escaping @MainActor () -> Void) -> () -> Void {
        let observation = CoreAudioVolumeObservation(onChange: onChange)
        return { observation.stop() }
    }
}

/// The default output device and its volume property, shared by what reads and sets the volume and what listens to it.
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

/// Listens to the default output device's volume and re-binds when another device becomes the default.
private final class CoreAudioVolumeObservation {
    private typealias Listener = (object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)

    private var onChange: (@MainActor () -> Void)?
    private var systemListener: Listener?
    private var deviceListener: Listener?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        systemListener = add(AudioObjectID(kAudioObjectSystemObject), CoreAudioProperties.defaultDevice) { [weak self] in
            self?.bind()
            self?.onChange?()
        }
        bind()
    }

    isolated deinit { stop() }

    func stop() {
        [systemListener, deviceListener].compactMap { $0 }.forEach(remove)
        systemListener = nil
        deviceListener = nil
        onChange = nil
    }

    private func bind() {
        deviceListener.map(remove)
        deviceListener = nil
        guard let device = CoreAudioProperties.defaultDeviceID(), CoreAudioProperties.has(device, CoreAudioProperties.volume) else { return }
        deviceListener = add(device, CoreAudioProperties.volume) { [weak self] in self?.onChange?() }
    }

    private func add(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ action: @escaping @MainActor () -> Void) -> Listener? {
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { action() } }
        var address = address
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
        return (object, address, block)
    }

    private func remove(_ listener: Listener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(listener.object, &address, .main, listener.block)
    }
}
