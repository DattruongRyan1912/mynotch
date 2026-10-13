import AudioToolbox
import CoreAudio

/// Output volume as the user sees it.
nonisolated struct VolumeState: Equatable, Sendable {
    /// 0...1.
    var level: Float
    var muted: Bool
}

/// Source of output volume changes; faked in tests.
protocol VolumeMonitoring: AnyObject {
    /// Calls `onChange` whenever the default output device's volume or mute changes, until `stop()`.
    /// A device without a volume control (many HDMI and aggregate devices) produces no events.
    func start(_ onChange: @escaping @MainActor (VolumeState) -> Void)
    func stop()
}

/// Listens to the default output device through CoreAudio and re-binds when the default device changes.
final class VolumeMonitor: VolumeMonitoring {
    private typealias Listener = (object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)

    private static let defaultDevice = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static let volume = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static let mute = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    /// Some devices expose mute only per channel; channel 1 is the left one.
    private static let muteChannel1 = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: 1)

    private var onChange: (@MainActor (VolumeState) -> Void)?
    private var systemListener: Listener?
    private var deviceListeners: [Listener] = []
    /// The mute property of the bound device, nil when it has none.
    private var muteAddress: AudioObjectPropertyAddress?

    init() {}

    isolated deinit { stop() }

    func start(_ onChange: @escaping @MainActor (VolumeState) -> Void) {
        stop()
        self.onChange = onChange
        systemListener = add(AudioObjectID(kAudioObjectSystemObject), Self.defaultDevice) { [weak self] in self?.bind() }
        bind()
    }

    func stop() {
        ([systemListener].compactMap { $0 } + deviceListeners).forEach(remove)
        systemListener = nil
        deviceListeners = []
        muteAddress = nil
        onChange = nil
    }

    private func bind() {
        deviceListeners.forEach(remove)
        deviceListeners = []
        muteAddress = nil
        var address = Self.defaultDevice
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return }
        var volume = Self.volume
        guard AudioObjectHasProperty(device, &volume) else { return }
        muteAddress = [Self.mute, Self.muteChannel1].first { var address = $0; return AudioObjectHasProperty(device, &address) }
        for address in [Self.volume] + [muteAddress].compactMap({ $0 }) {
            if let listener = add(device, address, { [weak self] in self?.report(device) }) {
                deviceListeners.append(listener)
            }
        }
    }

    private func report(_ device: AudioObjectID) {
        guard let level = Self.read(Float32.self, device, Self.volume) else { return }
        let muted = muteAddress.flatMap { Self.read(UInt32.self, device, $0) }.map { $0 != 0 } ?? false
        onChange?(VolumeState(level: min(max(level, 0), 1), muted: muted))
    }

    private static func read<T: Numeric & BitwiseCopyable>(_ type: T.Type, _ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
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
