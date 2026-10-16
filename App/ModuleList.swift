import AIAgentsModule
import BatteryModule
import CalendarModule
import ClipboardModule
import LockScreenModule
import MediaModule
import MyNotchCore
import PerformanceModule
import PetModule
import PortsModule
import ScreenshotModule
import ShelfModule
import ShortcutsModule
import SystemActivitiesModule
import TimerModule
import TodoModule
import TranslationModule
import WindowLayoutModule

/// The ONLY place modules are wired into the app. Add one line per new module.
enum ModuleList {
    /// `activities` is the center every module publishes to; the cat reads it to know when the notch is free.
    static func make(activities: ActivityCenter) -> [any FeatureModule] {
        [
            ClipboardModule(),
            MediaModule(adapterScript: MediaAdapterLocation.scriptURL, adapterFramework: MediaAdapterLocation.frameworkURL),
            TranslationModule(),
            CalendarModule(),
            TodoModule(),
            ScreenshotModule(),
            AIAgentsModule(),
            BatteryModule(),
            ShortcutsModule(),
            TimerModule(),
            PerformanceModule(),
            PortsModule(),
            PetModule(activities: activities),
            ShelfModule(),
            SystemActivitiesModule(),
            LockScreenModule(),
            WindowLayoutModule(),
        ]
    }
}
