import BatteryModule
import CalendarModule
import ClipboardModule
import MediaModule
import MyNotchCore
import TranslationModule

/// The ONLY place modules are wired into the app. Add one line per new module.
enum ModuleList {
    static func make() -> [any FeatureModule] {
        [
            ClipboardModule(),
            MediaModule(adapterScript: MediaAdapterLocation.scriptURL, adapterFramework: MediaAdapterLocation.frameworkURL),
            TranslationModule(),
            CalendarModule(),
            BatteryModule(),
        ]
    }
}
