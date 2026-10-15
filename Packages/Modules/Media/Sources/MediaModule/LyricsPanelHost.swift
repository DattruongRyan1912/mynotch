import MyNotchCore
import SwiftUI

/// Ties the floating lyrics panel to the module's settings and to the store, for as long as the module runs: the settings say
/// whether the panel is up and how it looks, the store tells the Media tab's button, and where the user leaves the panel is
/// written back to the settings.
final class LyricsPanelHost {
    let controller: LyricsPanelController
    let model = LyricsPanelModel()
    private let store: NowPlayingStore
    private let settings: ModuleSettings
    private let keys: MediaSettingsKeys

    init(
        store: NowPlayingStore, settings: ModuleSettings, scheduler: any Scheduler,
        displays: @escaping @MainActor () -> [PanelDisplay], present: @escaping (NSPanel) -> Void
    ) {
        self.store = store
        self.settings = settings
        let keys = MediaSettingsKeys(settings)
        self.keys = keys
        controller = LyricsPanelController(
            scheduler: scheduler, placement: settings.value(keys.lyricsPanelFrames), displays: displays, present: present,
            onPlacementChange: { settings.set($0, for: keys.lyricsPanelFrames) }
        )
        controller.onCloseRequested = { [weak self] in self?.setShown(false) }
    }

    /// Makes the panel what the settings say. Safe to call again whatever changed: a panel that is up is not brought forward.
    func apply() {
        model.fontSize = settings.value(keys.lyricsPanelFontSize)
        controller.apply(opacity: settings.value(keys.lyricsPanelOpacity), clickThrough: settings.value(keys.lyricsPanelClickThrough))
        let isShown = settings.value(keys.lyricsPanel)
        store.setLyricsPanelShown(isShown)
        if isShown {
            if !controller.isShown {
                controller.show(content: AnyView(LyricsPanelView(store: store, model: model, presence: controller.presence)))
            }
        } else {
            controller.hide()
        }
    }

    /// The button and the hotkey: the setting flips, and the panel follows it at once.
    func toggle() {
        setShown(!settings.value(keys.lyricsPanel))
    }

    /// The setting says whether the panel is up, and the panel follows it at once.
    private func setShown(_ isShown: Bool) {
        settings.set(isShown, for: keys.lyricsPanel)
        apply()
    }

    /// Takes the panel off the screen without touching the setting, so it is there again when the module starts.
    func close() {
        controller.hide()
        store.setLyricsPanelShown(false)
    }
}
