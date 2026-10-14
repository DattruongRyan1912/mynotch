import MyNotchCore
import SwiftUI

/// The length each type starts at, in minutes. Names and defaults in one place, shared by the running module and the
/// Settings rows.
struct TimerSettingsKeys {
    let task: SettingKey<Int>
    let reminder: SettingKey<Int>
    let rest: SettingKey<Int>

    init(_ settings: ModuleSettings) {
        func key(_ name: String, _ kind: TimerKind) -> SettingKey<Int> {
            settings.key(name, default: kind.defaultMinutes, clampedTo: TimerKind.minutesRange)
        }
        task = key("taskMinutes", .task)
        reminder = key("reminderMinutes", .reminder)
        rest = key("breakMinutes", .rest)
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
        }
    }
}
