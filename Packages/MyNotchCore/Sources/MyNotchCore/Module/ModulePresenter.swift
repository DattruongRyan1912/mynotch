import SwiftUI

/// Module-scoped facade over the app's `NotchPresenter`: a module can open only its own tab, and once the module
/// stops its late callbacks cannot toast, open or close the notch.
public final class ModulePresenter {
    private let presenter: any NotchPresenter
    private let module: ModuleID
    private var isActive = true

    init(presenter: any NotchPresenter, module: ModuleID) {
        self.presenter = presenter
        self.module = module
    }

    /// Opens the notch on this module's own tab.
    public func open() {
        guard isActive else { return }
        presenter.open(tab: module)
    }

    public func showToast(_ content: AnyView, duration: Duration) {
        guard isActive else { return }
        presenter.showToast(content, duration: duration)
    }

    public func close() {
        guard isActive else { return }
        presenter.close()
    }

    /// Called by `ModuleContext.cancelAll()` when the module stops; makes this facade inert.
    func invalidate() {
        isActive = false
    }
}
