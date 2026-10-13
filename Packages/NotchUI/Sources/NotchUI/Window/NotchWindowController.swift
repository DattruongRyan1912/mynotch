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
        panel.onCancel = { [weak model] in model?.close() }
        panel.onResignKey = { [weak self] in self?.panelDidResignKey() }
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
            panel.allowsKeyStatus = false
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
        panel.allowsKeyStatus = false
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

    /// Gives the panel the keyboard while an open tab accepts it, and hands it back to the app in front otherwise.
    /// The panel is non-activating, so MyNotch never becomes the active app.
    private func setTakesKeyboard(_ takesKeyboard: Bool) {
        guard takesKeyboard != panel.allowsKeyStatus else { return }
        panel.allowsKeyStatus = takesKeyboard
        if takesKeyboard {
            // An ordered-out panel must not take the keyboard where nobody can see it.
            if isVisible { panel.makeKey() }
        } else if isVisible, panel.isKeyWindow {
            // Ordering out returns key status to the app in front; ordering back in leaves it there.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    /// The user moved the keyboard elsewhere (another app or another MyNotch window), so the notch closes unless
    /// pinned. Resigning because the keyboard is no longer wanted (tab switch, toast, close) changes nothing.
    private func panelDidResignKey() {
        guard panel.allowsKeyStatus, model.state.isExpanded, !model.isPinned else { return }
        model.close()
    }

    private func observe() {
        observation = Task { [weak self, activities, registry, model] in
            for await (hasActivity, _, _, wantsKeyboard) in Observations({
                (
                    activities.current != nil,
                    model.displayState,
                    registry.contentHeight(for: model.displayState),
                    NotchKeyboardPolicy.wantsKeyboard(state: model.displayState, tabs: registry.tabs)
                )
            }) {
                guard let self else { return }
                self.model.hasActivity = hasActivity
                self.refreshHitTesting()
                self.setTakesKeyboard(wantsKeyboard)
            }
        }
    }
}
