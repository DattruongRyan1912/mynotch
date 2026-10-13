import SwiftUI

/// Lets modules drive the notch without knowing about windows or screens.
public protocol NotchPresenter: AnyObject {
    func open(tab: ModuleID)
    func showToast(_ content: AnyView, duration: Duration)
    func close()
}
