import AVFoundation

/// One microphone the person can record with.
nonisolated struct MicrophoneDevice: Equatable, Identifiable, Sendable {
    /// `AVCaptureDevice.uniqueID`.
    let id: String
    let name: String

    /// The microphones connected now. Listing them opens none and asks for no permission.
    static func available() -> [MicrophoneDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
            .map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// The microphone setting is one string: the system's default, none, or a device's ID.
nonisolated enum MicrophoneChoice {
    static let systemDefault = "default"
    static let off = "off"

    /// What a recording is asked to use. A device that is not connected any more is the system's default, so unplugging a USB
    /// microphone never makes a recording fail.
    static func selection(for stored: String, available: [MicrophoneDevice]) -> MicrophoneSelection? {
        switch stored {
        case off: nil
        case systemDefault: .systemDefault
        default: available.contains { $0.id == stored } ? .device(stored) : .systemDefault
        }
    }
}
