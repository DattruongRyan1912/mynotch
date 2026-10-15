import AppKit
import CoreGraphics
import MyNotchCore
import Observation
import SwiftUI

/// `NotchPresenter` used by modules and the app; opens and toasts on the active screen's notch, and closes every screen's.
public final class NotchCoordinator: NotchPresenter {
    public weak var screens: ScreenManager?

    public init() {}

    public func open(tab: ModuleID) { screens?.activeController()?.model.open(tab: tab) }

    public func showToast(_ content: AnyView, duration: Duration) {
        screens?.activeController()?.model.showToast(content, duration: duration)
    }

    public func close() { screens?.allControllers().forEach { $0.model.close() } }

    /// Bound to the global "Toggle notch" shortcut.
    public func toggle() { screens?.activeController()?.model.toggle() }
}

/// One display that shows a notch right now, with the geometry that notch is drawn with.
nonisolated public struct NotchDisplay: Equatable, Sendable {
    public let id: CGDirectDisplayID
    /// The display's frame in AppKit screen coordinates.
    public let screenFrame: CGRect
    public let geometry: NotchGeometry

    public init(id: CGDirectDisplayID, screenFrame: CGRect, geometry: NotchGeometry) {
        self.id = id
        self.screenFrame = screenFrame
        self.geometry = geometry
    }
}

/// What the notch tells the windows of MyNotch that it does not own, which modules have no other way to learn: the
/// app-wide interface settings are not theirs to read. `ScreenManager` keeps the shared one up to date, and modules read
/// it (observably), so a change reaches them while they run. Tests make their own.
@Observable
public final class NotchInterface {
    public static let shared = NotchInterface()

    /// Whether the user keeps MyNotch's windows out of recordings (see `CaptureHidingFollower`).
    public var captureHiding: CaptureHiding
    /// The displays that show a notch now, which are not always all of them (display mode, fullscreen, hidden by the user).
    public var notches: [NotchDisplay]
    /// Whether the user wants a tap on the trackpad for a gesture (see `feel`).
    public var hapticsEnabled = true
    /// What the notch is drawn with, once `ScreenManager` has started; the source of `accent`, so what a module draws outside
    /// the notch's own view and what the notch gives its content through the environment are one colour.
    public private(set) var theme: NotchTheme?
    @ObservationIgnored private let performer: any HapticPerformer

    public init(captureHiding: CaptureHiding = .never, notches: [NotchDisplay] = [], performer: any HapticPerformer = SystemHapticPerformer()) {
        self.captureHiding = captureHiding
        self.notches = notches
        self.performer = performer
    }

    /// The accent the notch's controls are marked with: the user's choice or macOS's. For a window that hosts SwiftUI on its
    /// own (a floating panel), which does not inherit the notch's environment: put it in with
    /// `.environment(\.notchAccent, interface.accent)` (and `.tint(interface.accent)` for the system controls). Read in a
    /// view's body it makes the view redraw when the accent changes. The notch's purple until a theme is followed.
    public var accent: Color { theme?.accent ?? NotchTokens.accent }

    /// `accent` as plain components, for `Observations` and for drawing that is not SwiftUI; it is `Equatable`, so an
    /// observer hears of real changes only.
    public var accentRGB: NotchAccent.RGB { theme?.resolvedAccent ?? NotchAccent.RGB(red: 125, green: 92, blue: 255) }

    /// `accent` for a layer (`backgroundColor`, `strokeColor`) and Core Graphics drawing. A layer keeps the colour it was
    /// given: observe `accentRGB` (`for await rgb in Observations { interface.accentRGB }`) and set it again.
    public var accentCGColor: CGColor { theme?.resolvedAccent.cgColor ?? NSColor(NotchTokens.accent).cgColor }

    /// A light tap for something a gesture did, unless the user turned taps off. For the notch's own gestures and for a
    /// module whose gesture belongs with them (a window snapped into a tile).
    public func feel(_ haptic: Haptic) {
        guard hapticsEnabled else { return }
        performer.perform(haptic)
    }

    /// The displays among `displays` whose notch is visible, in display order so the list only changes when a notch
    /// that is shown does.
    static func visibleNotches(among displays: [(display: NotchDisplay, isVisible: Bool)]) -> [NotchDisplay] {
        displays.filter(\.isVisible).map(\.display).sorted { $0.id < $1.id }
    }

    /// Makes `captureHiding` and `hapticsEnabled` the user's settings now and again after every change, and takes `theme`
    /// (or one of its own) for the accent. The returned task ends it.
    @discardableResult
    func follow(_ settings: SettingsStore, theme: NotchTheme? = nil) -> Task<Void, Never> {
        self.theme = theme ?? NotchTheme(settings: settings)
        captureHiding = settings.value(InterfaceSettings.hideFromCapture)
        hapticsEnabled = settings.value(InterfaceSettings.haptics)
        return Task { [weak self] in
            for await (hiding, haptics) in Observations({ (settings.value(InterfaceSettings.hideFromCapture), settings.value(InterfaceSettings.haptics)) }) {
                self?.captureHiding = hiding
                self?.hapticsEnabled = haptics
            }
        }
    }
}
