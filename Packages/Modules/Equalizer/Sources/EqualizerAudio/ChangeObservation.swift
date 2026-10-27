import CoreAudio
import Foundation
import MyNotchCore
import Synchronization
import os

/// Listens to Core Audio for anything that can change which devices have sound on them, and says so (`deliver`) without
/// saying what: the manager looks at the whole picture itself. Dropping it removes every listener.
///
/// Watched: the default output device and the lists of processes and devices, plus, for every process, whether it is running
/// output and which output devices it uses, and, for every device, its sample rate. Those per-object listeners are
/// replaced whenever a process or a device comes or goes.
///
/// A device's volume is said apart (`volumeChanged`): it moves often, with every key press, and only changes the filters.
nonisolated final class ChangeObservation: Sendable {
    private static let logger = Log.logger(category: "equalizer")

    private let deliver: @Sendable () -> Void
    private let volumeChanged: @Sendable () -> Void
    /// The per-object listeners are replaced here, off the notification thread that asked for it.
    private let queue = DispatchQueue(label: "io.lucasvu.mynotch.equalizer.observe", qos: .utility)
    private let fixed = Mutex<[AudioPropertyListener]>([])
    private let perObject = Mutex<[AudioPropertyListener]>([])

    init(deliver: @escaping @Sendable () -> Void, volumeChanged: @escaping @Sendable () -> Void) {
        self.deliver = deliver
        self.volumeChanged = volumeChanged
    }

    /// Not in `init`: the listeners refer back to `self`.
    func start() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let changed: @Sendable () -> Void = { [weak self] in self?.deliver() }
        let restructured: @Sendable () -> Void = { [weak self] in self?.restructured() }
        let listeners = [
            Self.listener(system, kAudioHardwarePropertyDefaultOutputDevice, onChange: changed),
            Self.listener(system, kAudioHardwarePropertyProcessObjectList, onChange: restructured),
            Self.listener(system, kAudioHardwarePropertyDevices, onChange: restructured),
        ]
        fixed.withLock { $0 = listeners.compactMap { $0 } }
        queue.async { [weak self] in self?.watchObjects() }
    }

    deinit {
        fixed.withLock { $0 }.forEach { $0.remove() }
        perObject.withLock { $0 }.forEach { $0.remove() }
    }

    private func restructured() {
        queue.async { [weak self] in self?.watchObjects() }
        deliver()
    }

    private func watchObjects() {
        let old = perObject.withLock { listeners in
            defer { listeners = [] }
            return listeners
        }
        old.forEach { $0.remove() }
        let hardware = AudioHardwareSystem.shared
        let changed: @Sendable () -> Void = { [weak self] in self?.deliver() }
        let volume: @Sendable () -> Void = { [weak self] in self?.volumeChanged() }
        var fresh: [AudioPropertyListener?] = []
        for process in (try? hardware.processes) ?? [] {
            fresh.append(Self.listener(process.id, kAudioProcessPropertyIsRunningOutput, onChange: changed))
            fresh.append(Self.listener(process.id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput, onChange: changed))
        }
        for device in (try? hardware.devices) ?? [] {
            fresh.append(Self.listener(device.id, kAudioDevicePropertyNominalSampleRate, onChange: changed))
            var address = OutputVolume.address
            if AudioObjectHasProperty(device.id, &address) {
                fresh.append(Self.listener(device.id, address.mSelector, scope: address.mScope, onChange: volume))
            }
        }
        perObject.withLock { $0 = fresh.compactMap { $0 } }
    }

    /// An object that went away between being listed and being listened to is not worth more than a debug line.
    private static func listener(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        onChange: @escaping @Sendable () -> Void
    ) -> AudioPropertyListener? {
        do {
            return try AudioPropertyListener(object: object, selector: selector, scope: scope, onChange: onChange)
        } catch {
            logger.debug("Could not listen to an audio object: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
