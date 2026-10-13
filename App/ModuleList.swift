import BatteryModule
import ClipboardModule
import MyNotchCore

/// The ONLY place modules are wired into the app. Add one line per new module.
enum ModuleList {
    static func make() -> [any FeatureModule] {
        [
            ClipboardModule(),
            BatteryModule(),
        ]
    }
}
