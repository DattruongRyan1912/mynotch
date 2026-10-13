import MyNotchCore
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
