import AppKit
import MyNotchCore
import SwiftUI

/// Owns one screen's panel, view model and pointer hit-testing.
final class NotchWindowController {
    private(set) var displayID: CGDirectDisplayID
    let model: NotchViewModel
    private(set) var geometry: NotchGeometry
    private(set) var isVisible = false
    var sharingType: NSWindow.SharingType { panel.sharingType }
    private var screenFrame: CGRect
    private let panel: NotchPanel
    private let hosting: FirstMouseHostingView<NotchRootView>
    private let registry: ModuleRegistry
    private let activities: ActivityCenter
    private let captureHiding: () -> CaptureHiding
    private var observation: Task<Void, Never>?
    #if DEBUG
    private let trace: NotchWindowTrace
    #endif
    /// Tells the model when the window can be seen, which stops the timers and animations in it while it cannot.
    private var occlusionObserver: NSObjectProtocol?
    /// Last keyboard focus decision; the panel makes itself key only when it turns true.
    private var lastFocus = false
    /// Created on the first hand-back; see `KeyboardReturn`.
    private var keySink: KeySinkPanel?
    /// Strip height seen by the last observation, so only a show or hide is logged.
    private var lastStripHeight: CGFloat = 0
    /// Which activities were primary and in bubbles at the last observation, so only a change is logged.
    private var lastActivityIDs = ""
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
        delays: @escaping () -> (open: Duration, close: Duration),
        captureHiding: @escaping () -> CaptureHiding
    ) {
        self.displayID = displayID
        self.registry = registry
        self.activities = activities
        self.captureHiding = captureHiding
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
        NotchPerf.start()
        updateOnScreen()
        // Before the panel can be shown, so a recorder never sees a frame of a notch that was meant to be hidden.
        refreshSharingType()
        // Also for what no one here does: a display that sleeps, a screen that locks, a window covered.
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateOnScreen() }
        }
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
        // The panel may hold fewer or more bubbles with the new geometry.
        model.bubbleCount = CompactAccessories.bubbleCount(activities: activities, geometry: newGeometry)
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
            refreshSharingType()
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
        updateOnScreen()
    }

    private func updateOnScreen() {
        let onScreen = NotchPresence.isOnScreen(isVisible: isVisible && panel.isVisible, occlusion: panel.occlusionState)
        guard onScreen != model.isOnScreen else { return }
        NotchLog.record("onScreen \(onScreen) \(panel.logSummary)")
        model.isOnScreen = onScreen
    }

    /// Applies the setting to the notch's state right now, for the moments the observation loop would be too late.
    func refreshSharingType() {
        applySharingType(captureHiding().sharingType(for: model.displayState))
    }

    private func applySharingType(_ type: NSWindow.SharingType) {
        guard panel.sharingType != type else { return }
        NotchLog.record(
            "sharing \(panel.sharingType.logName) -> \(type.logName) hiding=\(captureHiding().rawValue) display=\(model.displayState.logDescription)"
        )
        panel.sharingType = type
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
        let zone = zone(at: point, dragging: dropTab != nil)
        let inside = zone != .outside
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
            NotchLog.record("passthrough ignoresMouse=\(!inside) state=\(model.displayState.logDescription)")
        }
        let action = DropRouting.dragAction(
            dropTab: dropTab, inside: inside, isDragging: model.isDragging, startedInside: dragStartedInside, isRefresh: isRefresh
        )
        if case .enter(let tab) = action {
            model.dragEntered(tab: tab)
        } else if zone != model.hover {
            model.pointerMoved(to: zone)
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
        let inside = zone(at: point, dragging: false) != .outside
        dragStartedInside = inside
        if !inside { model.clickedOutside() }
    }

    func close() {
        observation?.cancel()
        observation = nil
        occlusionObserver.map(NotificationCenter.default.removeObserver)
        occlusionObserver = nil
        panel.allowsKeyStatus = false
        orderOut("controller closed")
        panel.close()
        keySink?.orderOut(nil)
        keySink?.close()
        keySink = nil
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

    /// What the pointer is over: the notch (pill, strip, open notch), a bubble beside it, or the list under it. The
    /// bubbles and the list come from the same `CompactAccessories` the view draws, so the two cannot disagree.
    private func zone(at point: CGPoint, dragging: Bool) -> PointerZone {
        let state = model.displayState
        let accessories = CompactAccessories(activities: activities, geometry: geometry, isListOpen: model.isListOpen, state: state)
        return geometry.pointerZone(
            at: point, state: state, contentHeight: registry.contentHeight(for: state, tabUnderToast: model.tabUnderToast),
            strip: activities.stripHeight, bubbles: accessories.bubbles, listRows: accessories.listRows, dragging: dragging, in: screenFrame
        )
    }

    /// The panel may become key while the shown tab accepts the keyboard, and hands the keyboard back to the app in
    /// front as soon as it does not (a tab switch, a close), in place and without hiding the notch; it is non-activating,
    /// so MyNotch never becomes the active app. It makes itself key only when focus starts being wanted, never on later
    /// updates, so a pinned notch does not grab the keyboard back after the user clicked another app.
    private func updateKeyboard(wants: Bool, focuses: Bool) {
        let plan = NotchKeyboardPolicy.panelKeyPlan(
            wants: wants, focuses: focuses, wasFocused: lastFocus, isKey: panel.isKeyWindow, isVisible: isVisible
        )
        // Before the hand-back, so the panel leaving key status is not taken for the user clicking elsewhere.
        if plan.allowsKeyStatus != panel.allowsKeyStatus {
            NotchLog.record("keyboard allowsKey=\(plan.allowsKeyStatus) isKey=\(panel.isKeyWindow)")
            panel.allowsKeyStatus = plan.allowsKeyStatus
        }
        if plan.handBack { handBackKeyboard() }
        if plan.makeKey {
            NotchLog.record("keyboard makeKey")
            panel.makeKey()
        }
        lastFocus = focuses
    }

    private func handBackKeyboard() {
        let strategy = KeyboardReturn.current
        let front = NSWorkspace.shared.frontmostApplication
        let frontIsOtherApp = front.map { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier } ?? false
        let steps = strategy.steps(frontIsOtherApp: frontIsOtherApp)
        NotchLog.record("keyboard hand-back strategy=\(strategy.rawValue) steps=\(steps.map(\.rawValue)) frontIsOtherApp=\(frontIsOtherApp) \(panel.logSummary)")
        for step in steps { perform(step, front: front) }
        NotchLog.record("keyboard hand-back done \(panel.logSummary)")
    }

    private func perform(_ step: KeyboardReturn.Step, front: NSRunningApplication?) {
        switch step {
        case .showSink:
            let sink = keySink ?? KeySinkPanel()
            keySink = sink
            // Inside the notch panel at the top edge, where nothing can be seen of a clear 1 pt window.
            sink.setFrame(CGRect(x: panel.frame.midX - 0.5, y: panel.frame.maxY - 1, width: 1, height: 1), display: false)
            sink.orderFrontRegardless()
        case .makeSinkKey: keySink?.makeKey()
        case .hideSink: keySink?.orderOut(nil)
        case .activateFrontApp: _ = front?.activate()
        case .orderNotchOut: orderOut("hand keyboard back")
        case .orderNotchIn: orderFront("hand keyboard back")
        }
    }

    /// The user moved the keyboard elsewhere (another app or another MyNotch window): treated like a click outside,
    /// so pinned and dragging notches stay open. Resigning because the keyboard is no longer wanted changes nothing.
    private func panelDidResignKey() {
        guard panel.allowsKeyStatus else { return }
        model.clickedOutside()
    }

    /// What the controller reacts to; any change of it runs `observe`'s loop body once.
    private struct Observed: Equatable {
        var hasActivity: Bool
        /// Ids and the count of what is hidden behind the bubbles, for the log; module ids and fixed activity ids only.
        var activityIDs: String
        var stripHeight: CGFloat
        /// Bubbles beside the notch, and rows of the list while it is open: both move the hit area.
        var bubbles: Int
        var listRows: Int
        var state: NotchState
        var contentHeight: CGFloat
        var wantsKeyboard: Bool
        var focusesKeyboard: Bool
        var isDragging: Bool
        /// Read through the setting, so a change of the setting runs the loop too.
        var sharingType: NSWindow.SharingType
    }

    private func observe() {
        observation = Task { [weak self, activities, registry, model] in
            for await observed in Observations({ [weak self] () -> Observed in
                let state = model.displayState
                let covered = model.tabUnderToast
                // The geometry is the controller's own; it only changes through `update`, which sets the bubble count itself.
                let geometry = self?.geometry
                let bubbles = geometry.map { CompactAccessories.bubbleCount(activities: activities, geometry: $0) } ?? 0
                return Observed(
                    hasActivity: activities.current != nil,
                    activityIDs: "primary=\(activities.current?.id ?? "-") others=\(activities.others.map(\.id)) hidden=\(activities.hiddenCount)",
                    stripHeight: activities.stripHeight,
                    bubbles: bubbles,
                    listRows: geometry.map {
                        CompactAccessories(activities: activities, geometry: $0, isListOpen: model.isListOpen, state: state).listRows
                    } ?? 0,
                    state: state,
                    contentHeight: registry.contentHeight(for: state, tabUnderToast: covered),
                    wantsKeyboard: NotchKeyboardPolicy.wantsKeyboard(state: state, tabUnderToast: covered, tabs: registry.tabs),
                    focusesKeyboard: NotchKeyboardPolicy.focusesKeyboard(
                        state: state, tabUnderToast: covered, tabs: registry.tabs, onPurpose: model.isOpenedOnPurpose
                    ),
                    isDragging: model.isDragging,
                    sharingType: self?.captureHiding().sharingType(for: state) ?? .readOnly
                )
            }) {
                guard let self else { return }
                let (hasActivity, stripHeight, state) = (observed.hasActivity, observed.stripHeight, observed.state)
                NotchLog.record(
                    "observed display=\(state.logDescription) activity=\(hasActivity) strip=\(stripHeight) bubbles=\(observed.bubbles) "
                        + "list=\(observed.listRows) contentHeight=\(observed.contentHeight) wantsKeyboard=\(observed.wantsKeyboard) "
                        + "focusesKeyboard=\(observed.focusesKeyboard) dragging=\(observed.isDragging)"
                )
                self.model.hasActivity = hasActivity
                self.model.bubbleCount = observed.bubbles
                if observed.activityIDs != self.lastActivityIDs {
                    NotchLog.record("activities \(observed.activityIDs) bubbles=\(observed.bubbles)")
                    self.lastActivityIDs = observed.activityIDs
                }
                if stripHeight != self.lastStripHeight {
                    // The panel is not touched for a strip: only the hit area below changes, in `refreshHitTesting`.
                    NotchLog.record("strip \(self.lastStripHeight) -> \(stripHeight) display=\(state.logDescription) \(self.panel.logSummary)")
                    self.lastStripHeight = stripHeight
                }
                // A finished drag (drop, or the pointer left) must not leave its types behind for later refreshes.
                if !observed.isDragging { self.dragTypes = [] }
                self.applySharingType(observed.sharingType)
                self.refreshHitTesting()
                self.updateKeyboard(wants: observed.wantsKeyboard, focuses: observed.focusesKeyboard)
            }
        }
    }
}
