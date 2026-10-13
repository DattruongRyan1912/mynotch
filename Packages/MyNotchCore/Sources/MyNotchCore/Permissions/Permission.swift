/// System permissions a module can require.
nonisolated public enum Permission: Hashable, Sendable {
    case accessibility
    case screenRecording
    case calendars
    case reminders
    case bluetooth
    case automation(bundleID: String)
    case microphone

    public var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .calendars: "Calendars"
        case .reminders: "Reminders"
        case .bluetooth: "Bluetooth"
        case .automation(let bundleID): "Automation (\(bundleID))"
        case .microphone: "Microphone"
        }
    }

    /// Deep link into the matching System Settings privacy pane.
    public var settingsURL: String {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        return switch self {
        case .accessibility: base + "Privacy_Accessibility"
        case .screenRecording: base + "Privacy_ScreenCapture"
        case .calendars: base + "Privacy_Calendars"
        case .reminders: base + "Privacy_Reminders"
        case .bluetooth: base + "Privacy_Bluetooth"
        case .automation: base + "Privacy_Automation"
        case .microphone: base + "Privacy_Microphone"
        }
    }
}

nonisolated public enum PermissionStatus: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}
