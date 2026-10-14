import CoreAudio

/// Sets the default output device's volume and mute through CoreAudio. Nothing is cached: the default device can
/// change between two key presses.
final class SystemVolumeControl: VolumeControlling {
    init() {}

    /// nil when the device has no volume that can be set: many HDMI and aggregate devices only report one.
    func read() -> VolumeState? {
        guard let device = settableVolumeDevice(),
              let level = CoreAudioOutput.read(Float32.self, device, CoreAudioOutput.volume) else { return nil }
        let muted = CoreAudioOutput.muteAddresses(of: device).first
            .flatMap { CoreAudioOutput.read(UInt32.self, device, $0) }.map { $0 != 0 } ?? false
        return VolumeState(level: min(max(level, 0), 1), muted: muted)
    }

    var canMute: Bool {
        guard let device = CoreAudioOutput.defaultDeviceID() else { return false }
        let addresses = CoreAudioOutput.muteAddresses(of: device)
        return !addresses.isEmpty && addresses.allSatisfy { CoreAudioOutput.isSettable(device, $0) }
    }

    func setLevel(_ level: Float) -> Bool {
        guard let device = settableVolumeDevice() else { return false }
        return CoreAudioOutput.write(Float32(min(max(level, 0), 1)), device, CoreAudioOutput.volume)
    }

    func setMuted(_ muted: Bool) -> Bool {
        guard let device = CoreAudioOutput.defaultDeviceID() else { return false }
        let addresses = CoreAudioOutput.muteAddresses(of: device)
        guard !addresses.isEmpty else { return false }
        let value: UInt32 = muted ? 1 : 0
        return addresses.map { CoreAudioOutput.write(value, device, $0) }.allSatisfy { $0 }
    }

    private func settableVolumeDevice() -> AudioObjectID? {
        guard let device = CoreAudioOutput.defaultDeviceID(), CoreAudioOutput.isSettable(device, CoreAudioOutput.volume) else { return nil }
        return device
    }
}
