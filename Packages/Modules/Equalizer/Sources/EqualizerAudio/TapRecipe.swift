import CoreAudio
import Foundation

/// What a pipeline asks Core Audio for, as plain values, so tests can read them without touching a device.
nonisolated enum TapRecipe {
    static func name(deviceUID: String) -> String { "MyNotch EQ \(deviceUID)" }

    /// The audio that processes other than MyNotch send to the first stream of one device. Silenced while tapped
    /// (and back by itself when MyNotch quits or crashes), because the replay is what the user should hear.
    static func tapDescription(deviceUID: String, excluding processes: [AudioObjectID]) -> CATapDescription {
        let description = CATapDescription(excludingProcesses: processes, deviceUID: deviceUID, stream: 0)
        description.name = name(deviceUID: deviceUID)
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        return description
    }

    /// A private aggregate device on that one device plus the tap, as `SystemAudioTap` builds it. Its IO proc reads
    /// the tap as input and writes the device's output.
    static func aggregate(deviceUID: String, tapUID: String, aggregateUID: String = UUID().uuidString) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: name(deviceUID: deviceUID),
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            // Run from the start rather than wait for the first tapped audio: a denied tap then still delivers
            // its silence, and starting never waits.
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
        ]
    }
}
