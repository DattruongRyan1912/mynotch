import AppKit

/// Keeps one black band over the menu bar of each display that is to have one. `ScreenManager` tells it what it knows (the setting, the
/// displays, which are fullscreen) whenever any of that may have changed; it does nothing when nothing did.
final class MenuBarBands {
    private let interface: NotchInterface
    private(set) var windows: [CGDirectDisplayID: MenuBarBandWindow] = [:]

    init(interface: NotchInterface = .shared) {
        self.interface = interface
    }

    func update(mode: BlackMenuBar, screens: [MenuBarBandScreen], fullscreen: Set<CGDirectDisplayID>) {
        apply(MenuBarBand.plan(mode: mode, screens: screens, fullscreen: fullscreen))
    }

    /// Takes every band away.
    func close() {
        apply([:])
    }

    private func apply(_ plan: [CGDirectDisplayID: CGRect]) {
        for (id, window) in windows where plan[id] == nil {
            window.orderOut(nil)
            window.close()
            windows[id] = nil
        }
        for (id, frame) in plan {
            if let window = windows[id] {
                if window.frame != frame { window.setFrame(frame, display: true) }
                if !window.isVisible { window.orderFrontRegardless() }
            } else {
                let window = MenuBarBandWindow(frame: frame, interface: interface)
                windows[id] = window
                window.orderFrontRegardless()
            }
        }
    }
}
