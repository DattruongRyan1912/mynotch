import AppKit
import MyNotchCore
import SwiftUI

/// Owns one screen's panel, view model and pointer hit-testing.
final class NotchWindowController {
    let displayID: CGDirectDisplayID
    let model: NotchViewModel
    private(set) var geometry: NotchGeometry
    private var screenFrame: CGRect
    private let panel: NotchPanel
    private let registry: ModuleRegistry
    private let activities: ActivityCenter
    private var isVisible = false

    init(
        displayID: CGDirectDisplayID,
        screen: ScreenDescriptor,
        config: NotchLayoutConfig,
        scheduler: any Scheduler,
        registry: ModuleRegistry,
        activities: ActivityCenter,
        delays: @escaping () -> (open: Duration, close: Duration)
    ) {
        self.displayID = displayID
        self.registry = registry
        self.activities = activities
        screenFrame = screen.frame
        geometry = NotchGeometry(screen: screen, config: config)
        model = NotchViewModel(scheduler: scheduler, availableTabs: { [weak registry] in registry?.tabs.map(\.id) ?? [] }, delays: delays)
        panel = NotchPanel(frame: geometry.panelFrame(in: screen.frame))
        installContent()
        observeActivities()
    }

    func update(screen: ScreenDescriptor, config: NotchLayoutConfig) {
        screenFrame = screen.frame
        geometry = NotchGeometry(screen: screen, config: config)
        panel.setFrame(geometry.panelFrame(in: screen.frame), display: true)
        installContent()
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            if model.isPointerInside { model.pointerExited() }
            model.close()
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        }
    }

    /// Called for every pointer move; flips click-through and drives hover state.
    func pointerMoved(to point: CGPoint) {
        guard isVisible else { return }
        let inside = currentHitRect().contains(point)
        panel.ignoresMouseEvents = !inside
        if inside, !model.isPointerInside {
            model.pointerEntered()
        } else if !inside, model.isPointerInside {
            model.pointerExited()
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    private func currentHitRect() -> CGRect {
        let state = model.displayState
        return geometry.hitRect(for: state, contentHeight: registry.contentHeight(for: state), in: screenFrame)
    }

    private func installContent() {
        let root = NotchRootView(model: model, activities: activities, registry: registry, geometry: geometry)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: geometry.panelSize)
        panel.contentView = hosting
    }

    private func observeActivities() {
        Task { [weak self, activities] in
            for await hasActivity in Observations({ activities.current != nil }) {
                self?.model.hasActivity = hasActivity
            }
        }
    }
}
