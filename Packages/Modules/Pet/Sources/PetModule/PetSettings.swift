import AppKit
import MyNotchCore
import SwiftUI

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct PetSettingsKeys {
    /// The times the cat can be asked to fall asleep after, in minutes.
    static let sleepOptions = [2, 5, 10]

    /// Whether the cat is on the notch. On, which is the point of the module: it turns itself off in Settings, not by default.
    let show: SettingKey<Bool>
    /// The colour of the cat.
    let coat: SettingKey<CatCoat>
    /// A click on the cat mews. Off: a sound nobody asked for at a desk is not a gift.
    let meow: SettingKey<Bool>
    let sleepMinutes: SettingKey<Int>

    init(_ settings: ModuleSettings) {
        show = settings.key("show", default: true)
        coat = settings.key("coat", default: CatCoat.tabby)
        meow = settings.key("meow", default: false)
        sleepMinutes = settings.key("sleepMinutes", default: 5)
    }

    /// The sleep time as the cat has it: the option nearest to what is stored, so a value that is not one of the three still means one.
    static func snapped(sleepMinutes stored: Int) -> Int {
        sleepOptions.min { abs($0 - stored) < abs($1 - stored) } ?? 5
    }

    func tuning(_ settings: ModuleSettings) -> CatTuning {
        CatTuning(sleepAfter: TimeInterval(Self.snapped(sleepMinutes: settings.value(sleepMinutes))) * 60)
    }
}

/// Plain rows: the Settings page provides the Form and the section.
struct PetSettingsView: View {
    let keys: PetSettingsKeys
    let settings: ModuleSettings

    var body: some View {
        Group {
            Toggle(isOn: settings.binding(keys.show)) {
                Text("Hiện mèo trên notch")
                Text("Mèo chơi trên một dải dưới notch khi không có hoạt động nào khác, và nhường chỗ ngay khi có.")
            }
            Picker("Màu mèo", selection: settings.binding(keys.coat)) {
                ForEach(CatCoat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle(isOn: settings.binding(keys.meow)) {
                Text("Tiếng mèo khi bấm")
                Text("Bấm vào mèo để vuốt ve. Mèo kêu thêm một tiếng nếu bật mục này.")
            }
            Picker("Mèo ngủ sau", selection: sleepBinding) {
                ForEach(PetSettingsKeys.sleepOptions, id: \.self) { Text("\($0) phút không đụng tới máy").tag($0) }
            }
        }
    }

    private var sleepBinding: Binding<Int> {
        Binding(
            get: { PetSettingsKeys.snapped(sleepMinutes: settings.value(keys.sleepMinutes)) },
            set: { settings.set($0, for: keys.sleepMinutes) }
        )
    }
}
