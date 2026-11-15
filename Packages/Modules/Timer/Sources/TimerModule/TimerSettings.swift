import MyNotchCore
import SwiftUI

/// What the sound at the end of a countdown does ("Âm báo hết giờ").
nonisolated enum TimerAlertMode: String, Codable, CaseIterable, Sendable {
    case once, repeating, off

    var title: String {
        switch self {
        case .once: "Một lần"
        case .repeating: "Lặp đến khi tắt"
        case .off: "Không"
        }
    }
}

/// The system sounds on offer for the end of a countdown. A stored name that is not one of them plays the default.
nonisolated enum TimerAlertSound {
    static let `default` = "Glass"
    static let names = ["Glass", "Ping", "Hero", "Submarine"]

    static func resolved(_ stored: String) -> String { names.contains(stored) ? stored : `default` }
}

/// The module's settings: the length each type starts at, in minutes, and the sound at the end. Names and defaults in one
/// place, shared by the running module and the Settings rows.
struct TimerSettingsKeys {
    let task: SettingKey<Int>
    let reminder: SettingKey<Int>
    let rest: SettingKey<Int>
    let alertMode: SettingKey<TimerAlertMode>
    let alertSound: SettingKey<String>

    init(_ settings: ModuleSettings) {
        func key(_ name: String, _ kind: TimerKind) -> SettingKey<Int> {
            settings.key(name, default: kind.defaultMinutes, clampedTo: TimerKind.minutesRange)
        }
        task = key("taskMinutes", .task)
        reminder = key("reminderMinutes", .reminder)
        rest = key("breakMinutes", .rest)
        alertMode = settings.key("alertMode", default: TimerAlertMode.repeating)
        alertSound = settings.key("alertSound", default: TimerAlertSound.default)
    }

    func key(for kind: TimerKind) -> SettingKey<Int> {
        switch kind {
        case .task: task
        case .reminder: reminder
        case .rest: rest
        }
    }
}

struct TimerSettingsView: View {
    let settings: ModuleSettings
    let keys: TimerSettingsKeys

    var body: some View {
        Group {
            ForEach(TimerKind.allCases, id: \.self) { kind in
                let key = keys.key(for: kind)
                Stepper("\(kind.title): \(settings.value(key)) phút", value: settings.binding(key), in: TimerKind.minutesRange)
            }
            Picker("Âm báo hết giờ", selection: settings.binding(keys.alertMode)) {
                ForEach(TimerAlertMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Âm thanh", selection: settings.binding(keys.alertSound)) {
                ForEach(TimerAlertSound.names, id: \.self) { Text($0).tag($0) }
            }
            .disabled(settings.value(keys.alertMode) == .off)
        }
    }
}
