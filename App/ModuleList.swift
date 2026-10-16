import AIAgentsModule
import BatteryModule
import CalendarModule
import ClipboardModule
import LockScreenModule
import MediaModule
import MyNotchCore
import PerformanceModule
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
    static func make() -> [any FeatureModule] {
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
            ShelfModule(),
            SystemActivitiesModule(),
            LockScreenModule(),
            WindowLayoutModule(),
        ]
    }
}
