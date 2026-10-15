import AppKit
import MyNotchCore
import Observation
import SwiftUI

extension EnvironmentValues {
    /// The accent the user picked, for the notch's controls and for a tab's own marks (a selection, a progress bar).
    /// Outside a notch (a preview, a test) it is the notch's own purple.
    @Entry public var notchAccent: Color = NotchTokens.accent
}

/// What the notch is drawn with, read from the settings and from macOS. Reading `accent` or `glass` in a view's body makes
/// the view redraw when the setting changes, and `accent` also when macOS changes its own accent.
@Observable
public final class NotchTheme {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let systemAccent: () -> NotchAccent.RGB
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    /// What macOS told about its colours so far; a view that read the accent depends on it.
    private var systemColorChanges = 0

    public init(
        settings: SettingsStore,
        systemAccent: @escaping () -> NotchAccent.RGB = { SystemAccent.current() },
        notifications: NotificationCenter = .default
    ) {
        self.settings = settings
        self.systemAccent = systemAccent
        self.notifications = notifications
        observer = notifications.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemColorChanges += 1 }
        }
    }

    isolated deinit {
        observer.map(notifications.removeObserver)
    }

    public var resolvedAccent: NotchAccent.RGB {
        _ = systemColorChanges
        return settings.value(InterfaceSettings.accent).resolved(system: systemAccent())
    }

    public var accent: Color { resolvedAccent.color }

    /// The user's choice of glass. Whether the notch is glass right now also depends on its state: see `showsGlass`.
    public var glass: Bool { settings.value(InterfaceSettings.glass) }

    /// Glass is for the open notch only. The collapsed one has to match the hardware cutout, which is black.
    public static func showsGlass(enabled: Bool, state: NotchState) -> Bool {
        enabled && state.isExpanded
    }
}
