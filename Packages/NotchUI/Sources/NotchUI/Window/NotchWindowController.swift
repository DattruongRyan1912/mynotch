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
    #if DEBUG
    private let trace: NotchWindowTrace
    #endif
    /// Last keyboard focus decision; the panel makes itself key only when it turns true.
    private var lastFocus = false
    /// Pasteboard types of the drag in progress, empty when nothing is being dragged.
    private var dragTypes: [String] = []
    /// Whether the mouse button went down inside the notch, so a drag in progress started there (an item dragged out).
    private var dragStartedInside = false

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
        #if DEBUG
        trace = NotchWindowTrace(panel)
        #endif
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
        NotchLog.record("update display=\(displayID) panel \(panel.frame.logDescription) -> \(newGeometry.panelFrame(in: screen.frame).logDescription)")
        screenFrame = screen.frame
        geometry = newGeometry
        // The new shape first, then the frame: `setFrame(display: true)` draws at once, and it must not draw the old shape
        // in the new frame.
        hosting.rootView = NotchRootView(model: model, activities: activities, registry: registry, geometry: geometry)
        panel.setFrame(geometry.panelFrame(in: screen.frame), display: true)
        hosting.frame = CGRect(origin: .zero, size: geometry.panelSize)
        refreshHitTesting()
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            orderFront("visible")
            refreshHitTesting()
        } else {
            if model.isPointerInside { model.pointerExited() }
            // Closing also ends drag mode on the model; the drag's own types must not outlive the hide either.
            model.close()
            dragTypes = []
            panel.allowsKeyStatus = false
            lastFocus = false
            panel.ignoresMouseEvents = true
            orderOut("hidden")
        }
    }

    /// Called for every pointer move; flips click-through and drives hover and drag state. `dragTypes` are the
    /// pasteboard types of a drag in progress; one that a tab accepts enlarges the hit area and opens that tab.
    func pointerMoved(to point: CGPoint, dragTypes: [String]) {
        self.dragTypes = dragTypes
        updatePointer(point, isRefresh: false)
    }

    private func updatePointer(_ point: CGPoint, isRefresh: Bool) {
        guard isVisible else { return }
        let dropTab = dragTypes.isEmpty
            ? nil : DropRouting.tab(for: dragTypes, tabs: registry.tabs, preferring: model.displayState.shownTab(tabUnderToast: model.tabUnderToast))
        let inside = currentHitRect(dragging: dropTab != nil).contains(point)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
            NotchLog.record("passthrough ignoresMouse=\(!inside) state=\(model.displayState.logDescription)")
        }
        let action = DropRouting.dragAction(
            dropTab: dropTab, inside: inside, isDragging: model.isDragging, startedInside: dragStartedInside, isRefresh: isRefresh
        )
        if case .enter(let tab) = action {
            model.dragEntered(tab: tab)
        } else if inside, !model.isPointerInside {
            model.pointerEntered()
        } else if !inside, model.isPointerInside {
            model.pointerExited()
        }
        if action == .exit { model.dragExited() }
    }

    /// Called for every mouse-button press, inside this app or not; a press outside the notch closes it. A new press
    /// also ends any earlier drag, so its pasteboard types cannot linger. Hidden controllers still forget the previous
    /// press, so a stale "started inside" cannot suppress opening on a later drag.
    func mouseDown(at point: CGPoint) {
        dragTypes = []
        dragStartedInside = false
        guard isVisible else { return }
        let inside = currentHitRect().contains(point)
        dragStartedInside = inside
        if !inside { model.clickedOutside() }
    }

    func close() {
        observation?.cancel()
        observation = nil
        panel.allowsKeyStatus = false
        orderOut("controller closed")
        panel.close()
    }

    private func orderFront(_ reason: String) {
        NotchLog.record("orderFront reason=\(reason) \(panel.logSummary)")
        panel.orderFrontRegardless()
    }

    private func orderOut(_ reason: String) {
        NotchLog.record("orderOut reason=\(reason) \(panel.logSummary)")
        panel.orderOut(nil)
    }

    /// The shape can change while the mouse is still (hotkey, toast, activity), so re-check the pointer.
    private func refreshHitTesting() {
        updatePointer(NSEvent.mouseLocation, isRefresh: true)
    }

    private func currentHitRect(dragging: Bool = false) -> CGRect {
        let state = model.displayState
        let contentHeight = registry.contentHeight(for: state, tabUnderToast: model.tabUnderToast)
        return dragging
            ? geometry.dragHitRect(for: state, contentHeight: contentHeight, in: screenFrame)
            : geometry.hitRect(for: state, contentHeight: contentHeight, in: screenFrame)
    }

    /// The panel may become key while the shown tab accepts the keyboard, and hands the keyboard back to the app in
    /// front otherwise (once the notch collapses, never during a tab switch); it is non-activating, so MyNotch never
    /// becomes the active app. It makes itself key only when focus starts being wanted, never on later updates, so a
    /// pinned notch does not grab the keyboard back after the user clicked another app.
    private func updateKeyboard(wants: Bool, focuses: Bool, isExpanded: Bool) {
        let plan = NotchKeyboardPolicy.panelKeyPlan(
            wants: wants, focuses: focuses, wasFocused: lastFocus, isKey: panel.isKeyWindow, isVisible: isVisible, isExpanded: isExpanded
        )
        if plan.allowsKeyStatus != panel.allowsKeyStatus {
            NotchLog.record("keyboard allowsKey=\(plan.allowsKeyStatus) isKey=\(panel.isKeyWindow) expanded=\(isExpanded)")
            panel.allowsKeyStatus = plan.allowsKeyStatus
        }
        if !plan.handBack, !wants, isExpanded, panel.isKeyWindow {
            NotchLog.record("keyboard hand-back waits until the notch collapses")
        }
        if plan.handBack {
            // Ordering out returns key status to the app in front; ordering back in leaves it there. The plan only asks for
            // it once the notch is collapsed, because the panel blinks.
            orderOut("hand keyboard back")
            orderFront("hand keyboard back")
        }
        if plan.makeKey {
            NotchLog.record("keyboard makeKey expanded=\(isExpanded)")
            panel.makeKey()
        }
        lastFocus = focuses
    }

    /// The user moved the keyboard elsewhere (another app or another MyNotch window): treated like a click outside,
    /// so pinned and dragging notches stay open. Resigning because the keyboard is no longer wanted changes nothing.
    private func panelDidResignKey() {
        guard panel.allowsKeyStatus else { return }
        model.clickedOutside()
    }

    private func observe() {
        observation = Task { [weak self, activities, registry, model] in
            for await (hasActivity, state, contentHeight, wantsKeyboard, focusesKeyboard, isDragging) in Observations({
                let state = model.displayState
                let covered = model.tabUnderToast
                return (
                    activities.current != nil,
                    state,
                    registry.contentHeight(for: state, tabUnderToast: covered),
                    NotchKeyboardPolicy.wantsKeyboard(state: state, tabUnderToast: covered, tabs: registry.tabs),
                    NotchKeyboardPolicy.focusesKeyboard(
                        state: state, tabUnderToast: covered, tabs: registry.tabs, onPurpose: model.isOpenedOnPurpose
                    ),
                    model.isDragging
                )
            }) {
                guard let self else { return }
                NotchLog.record(
                    "observed display=\(state.logDescription) activity=\(hasActivity) contentHeight=\(contentHeight) "
                        + "wantsKeyboard=\(wantsKeyboard) focusesKeyboard=\(focusesKeyboard) dragging=\(isDragging)"
                )
                self.model.hasActivity = hasActivity
                // A finished drag (drop, or the pointer left) must not leave its types behind for later refreshes.
                if !isDragging { self.dragTypes = [] }
                self.refreshHitTesting()
                self.updateKeyboard(wants: wantsKeyboard, focuses: focusesKeyboard, isExpanded: state.isExpanded)
            }
        }
    }
}
