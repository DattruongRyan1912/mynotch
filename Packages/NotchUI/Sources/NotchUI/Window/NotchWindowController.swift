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
    /// The panel's own appearance: nil, the system's, in every look. Forcing it dark made the glass read as dark frosted glass.
    var appearance: NSAppearance? { panel.appearance }
    /// This notch's display and geometry, as modules get them through `NotchInterface`.
    var display: NotchDisplay { NotchDisplay(id: displayID, screenFrame: screenFrame, geometry: geometry) }
    private var screenFrame: CGRect
    private let panel: NotchPanel
    private let hosting: FirstMouseHostingView<NotchRootView>
    private let theme: NotchTheme?
    /// The debug switches of the glass look, as read once when this notch was made; its root view is rebuilt with the same ones.
    private let glassSwitches: NotchGlassSwitches
    private let registry: ModuleRegistry
    private let activities: ActivityCenter
    private let captureHiding: () -> CaptureHiding
    private let swipesBetweenTabs: () -> Bool
    private let systemAllowsSwipe: () -> Bool
    /// The sensitivity of swiping to open and close, read at each gesture; nil when the user turned it off.
    private let swipeToOpen: () -> SwipeSensitivity?
    private let feel: (Haptic) -> Void
    private var swipe = TabSwipeRecognizer()
    private var openSwipe = NotchSwipeRecognizer()
    private var observation: Task<Void, Never>?
    #if DEBUG
    private let trace: NotchWindowTrace
    #endif
    /// Tells the model when the window can be seen, which stops the timers and animations in it while it cannot.
    private var occlusionObserver: NSObjectProtocol?
    /// Last keyboard focus decision; the panel makes itself key only when it turns true.
    private var lastFocus = false
    /// Hands the keyboard back to the app in front; see `KeyboardReturn`.
    private let keyboardHandBack = KeyboardHandBack()
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
        captureHiding: @escaping () -> CaptureHiding,
        swipesBetweenTabs: @escaping () -> Bool,
        systemAllowsSwipe: @escaping () -> Bool = { NSEvent.isSwipeTrackingFromScrollEventsEnabled },
        swipeToOpen: @escaping () -> SwipeSensitivity? = { nil },
        theme: NotchTheme? = nil,
        glassSwitches: NotchGlassSwitches = .default,
        feel: @escaping (Haptic) -> Void = { _ in }
    ) {
        self.displayID = displayID
        self.registry = registry
        self.activities = activities
        self.captureHiding = captureHiding
        self.swipesBetweenTabs = swipesBetweenTabs
        self.systemAllowsSwipe = systemAllowsSwipe
        self.swipeToOpen = swipeToOpen
        self.theme = theme
        self.glassSwitches = glassSwitches
        self.feel = feel
        screenFrame = screen.frame
        geometry = NotchGeometry(screen: screen, config: config)
        model = NotchViewModel(scheduler: scheduler, availableTabs: { [weak registry] in registry?.tabs.map(\.id) ?? [] }, delays: delays)
        panel = NotchPanel(frame: geometry.panelFrame(in: screen.frame))
        hosting = FirstMouseHostingView(
            rootView: NotchRootView(
                model: model, activities: activities, registry: registry, geometry: geometry, theme: theme, switches: glassSwitches
            )
        )
        hosting.frame = CGRect(origin: .zero, size: geometry.panelSize)
        panel.contentView = hosting
        #if DEBUG
        trace = NotchWindowTrace(panel)
        #endif
        hosting.onUnusedScroll = { [weak self] event in
            self?.handleScroll(
                phase: event.phase, momentumPhase: event.momentumPhase, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                naturalScrolling: event.isDirectionInvertedFromDevice
            )
        }
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
        hosting.rootView = NotchRootView(
            model: model, activities: activities, registry: registry, geometry: geometry, theme: theme, switches: glassSwitches
        )
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

    /// A scroll event nothing under the pointer used. A two-finger sideways swipe moves the open notch one tab along the
    /// tab bar, and a vertical one opens the collapsed notch (down) or closes the open one (up); the view only sees these
    /// while the pointer is over the notch, because the panel ignores the mouse elsewhere. `naturalScrolling` says whether
    /// the delta is the fingers' direction (the default) or the opposite, which only the vertical swipe cares about: it is
    /// about where the fingers go.
    func handleScroll(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, deltaX: CGFloat, deltaY: CGFloat, naturalScrolling: Bool = true) {
        swipeBetweenTabs(phase: phase, momentumPhase: momentumPhase, deltaX: deltaX, deltaY: deltaY)
        swipeOpenOrClosed(phase: phase, momentumPhase: momentumPhase, deltaX: deltaX, fingersDeltaY: naturalScrolling ? deltaY : -deltaY)
    }

    private func swipeBetweenTabs(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, deltaX: CGFloat, deltaY: CGFloat) {
        guard let step = swipe.feed(phase: phase, momentumPhase: momentumPhase, deltaX: deltaX, deltaY: deltaY) else { return }
        let tabs = registry.tabs.map(\.id)
        guard let target = step.target(
            state: model.state, tabs: tabs, enabled: swipesBetweenTabs(), systemAllows: systemAllowsSwipe()
        ) else { return }
        NotchLog.record("swipe \(step == .next ? "next" : "previous") \(model.state.logDescription) -> \(target.rawValue)")
        model.open(tab: target)
        feel(.alignment)
    }

    private func swipeOpenOrClosed(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, deltaX: CGFloat, fingersDeltaY: CGFloat) {
        guard let sensitivity = swipeToOpen() else { return }
        // `hover` is the part of the notch the pointer was last seen over, so a gesture that begins over a bubble, the list
        // or nothing at all is not a swipe on the notch.
        guard let step = openSwipe.feed(
            phase: phase, momentumPhase: momentumPhase, deltaX: deltaX, deltaY: fingersDeltaY, onNotch: model.hover == .notch,
            sensitivity: sensitivity
        ), let action = step.action(state: model.state, keptOpen: model.isPinned || model.isDragging) else { return }
        NotchLog.record("swipe \(step) \(model.state.logDescription) -> \(action)")
        switch action {
        // Like a hover: the pointer is on the notch and nothing was clicked, so a keyboard tab does not take the keyboard.
        case .open: model.open(tab: nil, onPurpose: false)
        case .close: model.close()
        }
        feel(.levelChange)
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
        keyboardHandBack.close()
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
        if plan.handBack { keyboardHandBack.returnKeyboard(from: panel) }
        if plan.makeKey {
            NotchLog.record("keyboard makeKey")
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
