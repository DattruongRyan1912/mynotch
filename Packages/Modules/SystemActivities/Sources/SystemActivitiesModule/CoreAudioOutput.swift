import AudioToolbox
import CoreAudio

/// The default output device and its volume and mute properties, shared by the monitor that listens to them and the
/// control that sets them.
enum CoreAudioOutput {
    static let defaultDevice = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    static let volume = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static let mute = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
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

    /// The device's mute: the main one, or for a device that exposes mute only per channel, the left and right ones.
    /// Empty when it has none.
    static func muteAddresses(of device: AudioObjectID) -> [AudioObjectPropertyAddress] {
        let candidates = [mute] + [1, 2].map {
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: $0)
        }
        let main = candidates[0]
        return has(device, main) ? [main] : candidates.dropFirst().filter { has(device, $0) }
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
