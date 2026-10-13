import AppKit
import MyNotchCore
import SwiftUI

/// Owns one screen's panel, view model and pointer hit-testing.
final class NotchWindowController {
    private(set) var displayID: CGDirectDisplayID
    let model: NotchViewModel
    private(set) var geometry: NotchGeometry
    private(set) var isVisible = false
    private var screenFrame: CGRect
    private let panel: NotchPanel
    private let hosting: FirstMouseHostingView<NotchRootView>
    private let registry: ModuleRegistry
    private let activities: ActivityCenter
    private var observation: Task<Void, Never>?

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
        hosting = FirstMouseHostingView(rootView: NotchRootView(model: model, activities: activities, registry: registry, geometry: geometry))
        hosting.frame = CGRect(origin: .zero, size: geometry.panelSize)
        panel.contentView = hosting
        observe()
    }

    /// Applies new screen facts or settings. Does nothing when nothing changed, and never replaces the
    /// hosting view, so SwiftUI state inside module tabs survives display and settings changes.
    func update(displayID: CGDirectDisplayID, screen: ScreenDescriptor, config: NotchLayoutConfig) {
        self.displayID = displayID
        let newGeometry = NotchGeometry(screen: screen, config: config)
        guard newGeometry != geometry || screen.frame != screenFrame else { return }
        screenFrame = screen.frame
        geometry = newGeometry
        panel.setFrame(geometry.panelFrame(in: screen.frame), display: true)
        hosting.frame = CGRect(origin: .zero, size: geometry.panelSize)
        hosting.rootView = NotchRootView(model: model, activities: activities, registry: registry, geometry: geometry)
        refreshHitTesting()
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            panel.orderFrontRegardless()
            refreshHitTesting()
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
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside, !model.isPointerInside {
            model.pointerEntered()
        } else if !inside, model.isPointerInside {
            model.pointerExited()
        }
    }

    /// Called for every mouse-button press, inside this app or not; a press outside the notch closes it.
    func mouseDown(at point: CGPoint) {
        guard isVisible, !currentHitRect().contains(point) else { return }
        model.clickedOutside()
    }

    func close() {
        observation?.cancel()
        observation = nil
        panel.orderOut(nil)
        panel.close()
    }

    /// The shape can change while the mouse is still (hotkey, toast, activity), so re-check the pointer.
    private func refreshHitTesting() {
        pointerMoved(to: NSEvent.mouseLocation)
    }

    private func currentHitRect() -> CGRect {
        let state = model.displayState
        return geometry.hitRect(for: state, contentHeight: registry.contentHeight(for: state), in: screenFrame)
    }

    private func observe() {
        observation = Task { [weak self, activities, registry, model] in
            for await (hasActivity, _, _) in Observations({
                (activities.current != nil, model.displayState, registry.contentHeight(for: model.displayState))
            }) {
                guard let self else { return }
                self.model.hasActivity = hasActivity
                self.refreshHitTesting()
            }
        }
    }
}
