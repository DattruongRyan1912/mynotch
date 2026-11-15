import AppKit
import MyNotchCore
import Observation
import SwiftUI

extension EnvironmentValues {
    /// The accent the user picked, for the notch's controls and for a tab's own marks (a selection, a progress bar).
    /// Outside a notch (a preview, a test) it is the notch's own purple.
    @Entry public var notchAccent: Color = NotchTokens.accent
}

/// What the notch is drawn with, read from the settings and from macOS. Reading `accent`, `look`, `glass` or `surface(for:)` in
/// a view's body makes the view redraw when the setting changes, and `accent` also when macOS changes its own accent.
@Observable
public final class NotchTheme {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let systemAccent: () -> NotchAccent.RGB
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var lookFollower: Task<Void, Never>?
    /// What macOS told about its colours so far; a view that read the accent depends on it.
    private var systemColorChanges = 0

    public convenience init(
        settings: SettingsStore,
        systemAccent: @escaping () -> NotchAccent.RGB = { SystemAccent.current() },
        notifications: NotificationCenter = .default
    ) {
        self.init(settings: settings, systemAccent: systemAccent, notifications: notifications, lookState: nil)
    }

    /// With a `lookState`, which the theme keeps in step with the look setting, from now on: the app's theme does, so that the
    /// text tokens follow the look. Any other theme (a test's, a preview's) leaves it alone.
    init(
        settings: SettingsStore,
        systemAccent: @escaping () -> NotchAccent.RGB = { SystemAccent.current() },
        notifications: NotificationCenter = .default,
        lookState: NotchLookState?
    ) {
        self.settings = settings
        self.systemAccent = systemAccent
        self.notifications = notifications
        if let lookState {
            lookState.isGlass = settings.value(InterfaceSettings.look) == .liquidGlass
            lookFollower = Task { [settings] in
                for await look in Observations({ settings.value(InterfaceSettings.look) }) { lookState.isGlass = look == .liquidGlass }
            }
        }
        observer = notifications.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemColorChanges += 1 }
        }
    }

    isolated deinit {
        lookFollower?.cancel()
        observer.map(notifications.removeObserver)
    }

    public var resolvedAccent: NotchAccent.RGB {
        let accent = settings.value(InterfaceSettings.accent)
        // Only the system accent depends on what macOS says; a fixed one is not redrawn when it changes its own.
        if accent == .system { _ = systemColorChanges }
        return accent.resolved(system: systemAccent())
    }

    public var accent: Color { resolvedAccent.color }

    /// The user's choice of the classic look's blur. Whether the notch is blurred right now also depends on its state: see
    /// `showsGlass`.
    public var glass: Bool { settings.value(InterfaceSettings.glass) }

    /// Black or Liquid Glass.
    public var look: NotchLook { settings.value(InterfaceSettings.look) }

    /// Whether the Liquid Glass carries a hint of the accent.
    public var glassTint: Bool { settings.value(InterfaceSettings.glassTint) }

    /// How clear the Liquid Glass is.
    public var glassClarity: NotchGlassClarity { settings.value(InterfaceSettings.glassClarity) }

    /// What the open notch's glass is made of.
    public var glassShape: NotchGlassShape { settings.value(InterfaceSettings.glassShape) }

    /// Both, for the plan. Reading it in a view's body makes the view redraw when either changes.
    var glassStyle: NotchGlassStyle { NotchGlassStyle(clarity: glassClarity, shape: glassShape) }

    /// What the notch's shape is filled with in `state`. Reading it in a view's body makes the view redraw when the look, the
    /// tint or the classic blur changes.
    public func surface(for state: NotchState) -> NotchSurface {
        .resolve(look: look, classicGlass: glass, tinted: glassTint, state: state)
    }

    /// The surface for a window or view of MyNotch that is not the notch (a floating panel): black or glass, never the open
    /// notch's blur. See `View.notchSurface(in:of:)`.
    public var floatingSurface: NotchSurface {
        .resolve(look: look, classicGlass: false, tinted: glassTint, state: .closed)
    }

    /// The classic look's blur is for the open notch only. The collapsed one has to match the hardware cutout, which is black.
    nonisolated public static func showsGlass(enabled: Bool, state: NotchState) -> Bool {
        enabled && state.isExpanded
    }
}
