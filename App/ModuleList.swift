import AIAgentsModule
import BatteryModule
import CalendarModule
import ClipboardModule
import EqualizerModule
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
    /// `activities` is the center every module publishes to; the pets read it to know when the notch is free. `equalizer` is the EQ state
    /// the Âm thanh module drives and the Media tab switches.
    static func make(activities: ActivityCenter, equalizer: EqualizerState) -> [any FeatureModule] {
        let translation = TranslationModule()
        let media = MediaModule(
            adapterScript: MediaAdapterLocation.scriptURL, adapterFramework: MediaAdapterLocation.frameworkURL, equalizer: equalizer
        )
        // The film a page plays is asked of the LLM the user set up for translating.
        media.languageModel = translation.languageModel
        return [
            ClipboardModule(),
            media,
            EqualizerModule(state: equalizer),
            translation,
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
