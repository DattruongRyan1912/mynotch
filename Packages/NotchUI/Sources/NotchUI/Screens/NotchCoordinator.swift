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

    public init(captureHiding: CaptureHiding = .never, notches: [NotchDisplay] = []) {
        self.captureHiding = captureHiding
        self.notches = notches
    }

    /// The displays among `displays` whose notch is visible, in display order so the list only changes when a notch
    /// that is shown does.
    static func visibleNotches(among displays: [(display: NotchDisplay, isVisible: Bool)]) -> [NotchDisplay] {
        displays.filter(\.isVisible).map(\.display).sorted { $0.id < $1.id }
    }

    /// Makes `captureHiding` the user's setting now and again after every change. The returned task ends it.
    @discardableResult
    func follow(_ settings: SettingsStore) -> Task<Void, Never> {
        captureHiding = settings.value(InterfaceSettings.hideFromCapture)
        return Task { [weak self] in
            for await hiding in Observations({ settings.value(InterfaceSettings.hideFromCapture) }) {
                self?.captureHiding = hiding
            }
        }
    }
}
