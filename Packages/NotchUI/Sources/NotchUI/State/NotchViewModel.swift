import MyNotchCore
import Observation
import SwiftUI

/// Per-screen notch state machine. Time is injected through `Scheduler`.
@Observable
public final class NotchViewModel {
    public private(set) var state: NotchState = .closed {
        didSet {
            guard state != oldValue else { return }
            NotchLog.record(
                "state \(oldValue.logDescription) -> \(state.logDescription) display=\(displayState.logDescription) "
                    + "tabUnderToast=\(tabUnderToast?.rawValue ?? "-") onPurpose=\(isOpenedOnPurpose) dragging=\(isDragging) "
                    + "pinned=\(isPinned) pointerInside=\(isPointerInside)"
            )
        }
    }
    public private(set) var toastContent: AnyView?
    public private(set) var lastTab: ModuleID?
    public private(set) var isPointerInside = false
    /// The part of the notch the pointer is over, which tells hovering the notch from hovering a bubble or the list.
    public private(set) var hover: PointerZone = .outside
    /// Set by the owner when the activity center has something to show.
    public var hasActivity = false {
        didSet {
            guard hasActivity != oldValue else { return }
            NotchLog.record("activity \(hasActivity) display=\(displayState.logDescription)")
        }
    }
    /// The width the current activity's strip asked for (`View.notchStripWidth`), and whose it is: it belongs to that activity alone, so
    /// another one never starts from it.
    private(set) var stripReport: StripReport?
    /// Set by the owner: how many bubbles of other activities are beside the notch. With none there is no list to open,
    /// and one that is open goes.
    public var bubbleCount = 0 {
        didSet {
            guard bubbleCount != oldValue else { return }
            NotchLog.record("bubbles \(bubbleCount) display=\(displayState.logDescription)")
            if bubbleCount == 0 { hideList() }
        }
    }
    /// The list of all live activities under the collapsed notch, opened by hovering a bubble. It is only what hangs
    /// under the notch: `state` does not change, so the notch itself neither resizes nor blinks.
    public private(set) var isListOpen = false {
        didSet {
            guard isListOpen != oldValue else { return }
            NotchLog.record("list \(isListOpen ? "open" : "closed") bubbles=\(bubbleCount) display=\(displayState.logDescription)")
        }
    }
    /// Keeps the notch open until unpinned or explicitly closed. Any window of MyNotch other than the notch
    /// (Settings, alerts, sheets, popovers, menus) counts as outside, so a module pins the notch while it
    /// shows such auxiliary UI.
    public var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            NotchLog.record("pinned \(isPinned)")
            isPinned ? pendingClose?.cancel() : scheduleCloseIfPointerOutside()
        }
    }
    public private(set) var isDragging = false
    /// Set by the window controller: the notch's window can be seen (shown, not covered, its display awake and its screen
    /// unlocked). Views that tick or animate stop while it is false; see `notchIsOnScreen`.
    public var isOnScreen = true
    /// The open tab a toast covers; the toast returns to it instead of closing the notch, and the view keeps
    /// it alive underneath so its state (search text, focus, scroll position) survives the toast.
    public private(set) var tabUnderToast: ModuleID?
    /// True when a click, the shortcut, the tab bar or a module opened the notch rather than hovering. Only then
    /// does a keyboard tab take the keyboard by itself.
    public private(set) var isOpenedOnPurpose = false

    /// The width a strip asked for, which the notch is as wide as; 0 for an activity that has not asked.
    func stripWidth(for activity: String?) -> CGFloat {
        guard let activity, let report = stripReport, report.activity == activity else { return 0 }
        return report.width
    }

    /// A strip tells the notch the width it wants. The first of an activity is taken, a wider one at once, and a narrower one only if it
    /// is narrower by `StripWidth.shrinkThreshold` or more.
    func reportStripWidth(_ width: CGFloat, for activity: String) {
        let current = stripReport?.activity == activity ? stripReport?.width : nil
        let settled = StripWidth.settle(current: current, reported: max(width, 0))
        guard settled != current else { return }
        stripReport = StripReport(activity: activity, width: settled)
        NotchLog.record("strip width \(Int(settled)) display=\(displayState.logDescription)")
    }

    /// What the view should render: `closed` becomes `compact` while an activity is live.
    public var displayState: NotchState {
        state == .closed && hasActivity ? .compact : state
    }

    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let availableTabs: () -> [ModuleID]
    @ObservationIgnored private let delays: () -> (open: Duration, close: Duration)
    @ObservationIgnored private var pendingOpen: ScheduledAction?
    @ObservationIgnored private var pendingList: ScheduledAction?
    @ObservationIgnored private var pendingClose: ScheduledAction?
    @ObservationIgnored private var toastTimer: ScheduledAction?
    /// A toast is shown for at least its duration; only after that may a pointer exit close it.
    @ObservationIgnored private var toastExpired = true

    public init(
        scheduler: any Scheduler,
        availableTabs: @escaping () -> [ModuleID],
        delays: @escaping () -> (open: Duration, close: Duration)
    ) {
        self.scheduler = scheduler
        self.availableTabs = availableTabs
        self.delays = delays
    }

    /// The pointer is over the notch itself (the collapsed pill and its strip, or the open notch).
    public func pointerEntered() {
        NotchLog.record("pointer entered state=\(state.logDescription)")
        setHover(.notch)
        pendingClose?.cancel()
        cancelPendingList()
        guard !state.isExpanded, pendingOpen == nil else { return }
        pendingOpen = scheduler.schedule(after: delays().open) { [weak self] in
            self?.pendingOpen = nil
            self?.show(tab: nil, onPurpose: false)
        }
    }

    public func pointerExited() {
        NotchLog.record("pointer exited state=\(state.logDescription)")
        setHover(.outside)
        pendingOpen?.cancel()
        pendingOpen = nil
        cancelPendingList()
        scheduleCloseIfPointerOutside()
    }

    /// The pointer is over a bubble: after the open delay the list of all activities opens under the notch. Over the
    /// bubbles the notch itself does not open, so a hover that began on the pill gives way to this one.
    public func bubblesEntered() {
        NotchLog.record("pointer entered bubbles state=\(state.logDescription)")
        setHover(.bubbles)
        pendingClose?.cancel()
        pendingOpen?.cancel()
        pendingOpen = nil
        guard !state.isExpanded, bubbleCount > 0, !isListOpen, pendingList == nil else { return }
        pendingList = scheduler.schedule(after: delays().open) { [weak self] in
            self?.pendingList = nil
            self?.showList()
        }
    }

    /// The pointer is over the open list, which keeps it open and keeps the notch from opening.
    public func listEntered() {
        NotchLog.record("pointer entered list state=\(state.logDescription)")
        setHover(.list)
        pendingClose?.cancel()
        pendingOpen?.cancel()
        pendingOpen = nil
        cancelPendingList()
    }

    /// For the window controller: the zone under the pointer changed.
    public func pointerMoved(to zone: PointerZone) {
        switch zone {
        case .outside: pointerExited()
        case .notch: pointerEntered()
        case .bubbles: bubblesEntered()
        case .list: listEntered()
        }
    }

    /// Opens the list at once, for a bubble that was activated without a hover (VoiceOver, the keyboard). Only a
    /// collapsed notch with a bubble has one.
    public func showList() {
        guard !state.isExpanded, bubbleCount > 0 else { return }
        cancelPendingList()
        isListOpen = true
    }

    public func hasTab(of module: ModuleID) -> Bool {
        availableTabs().contains(module)
    }

    /// Opens `module`'s tab on purpose. False, and nothing happens, when the module has no tab (a module of system
    /// notices) or is not a module at all (the debug publisher's).
    @discardableResult
    public func openTab(of module: ModuleID) -> Bool {
        guard hasTab(of: module) else { return false }
        open(tab: module)
        return true
    }

    /// Opens the tabs from the closed, compact or toast state.
    public func click() {
        if case .open = state { return }
        open(tab: nil)
    }

    public func toggle() {
        state.isExpanded ? close() : open(tab: nil)
    }

    /// Opens `tab`, or the last used tab, or the first available one, as an on-purpose open.
    public func open(tab: ModuleID?) {
        open(tab: tab, onPurpose: true)
    }

    /// As `open(tab:)`, with the choice of what kind of open it is. Only an on-purpose open (a click, the shortcut, the
    /// tab bar, a module) lets a tab that takes the keyboard take it from the app in front; one that is not (a hover, a
    /// swipe, with the pointer already on the notch and nothing clicked) leaves the keyboard where it is.
    public func open(tab: ModuleID?, onPurpose: Bool) {
        show(tab: tab, onPurpose: onPurpose)
    }

    private func show(tab: ModuleID?, onPurpose: Bool) {
        NotchLog.record("show tab=\(tab?.rawValue ?? "-") onPurpose=\(onPurpose) from=\(state.logDescription)")
        pendingOpen?.cancel()
        pendingOpen = nil
        hideList()
        pendingClose?.cancel()
        toastTimer?.cancel()
        toastExpired = true
        tabUnderToast = nil
        let tabs = availableTabs()
        let resolved = [tab, lastTab].compactMap { $0 }.first(where: tabs.contains) ?? tabs.first
        lastTab = resolved ?? lastTab
        toastContent = nil
        isOpenedOnPurpose = onPurpose
        state = .open(resolved)
    }

    /// Shows `content` for at least `duration`. Over an open tab the notch then returns to that tab
    /// instead of closing, so a toast never throws the user out of what they were doing.
    public func showToast(_ content: AnyView, duration: Duration) {
        NotchLog.record("toast duration=\(duration) from=\(state.logDescription)")
        pendingOpen?.cancel()
        pendingOpen = nil
        hideList()
        pendingClose?.cancel()
        toastTimer?.cancel()
        // A toast replacing another toast keeps the tab the first one covered.
        if case .open(let tab?) = state { tabUnderToast = tab }
        toastContent = content
        toastExpired = false
        state = .toast
        toastTimer = scheduler.schedule(after: duration) { [weak self] in
            self?.toastDidExpire()
        }
    }

    /// Closes the expanded notch for a click anywhere else, including any MyNotch window other than the notch
    /// (Settings, alerts, sheets, popovers, menus). Pinned notches stay open, so a module pins the notch for any
    /// auxiliary UI it shows; so do notches with a drag in progress.
    public func clickedOutside() {
        guard state.isExpanded || isListOpen, !isPinned, !isDragging else { return }
        NotchLog.record("close: click outside")
        close()
    }

    /// Closes the notch and ends pin and drag mode with it: a closed notch (hidden, toggled shut) must not stay stuck
    /// in drag mode, which would ignore outside clicks and keep a later toast open.
    public func close() {
        NotchLog.record("close from=\(state.logDescription)")
        pendingOpen?.cancel()
        pendingOpen = nil
        hideList()
        pendingClose?.cancel()
        toastTimer?.cancel()
        toastExpired = true
        tabUnderToast = nil
        toastContent = nil
        state = .closed
        isOpenedOnPurpose = false
        isDragging = false
        isPinned = false
    }

    public func setDragging(_ dragging: Bool) {
        guard dragging != isDragging else { return }
        NotchLog.record("drag mode dragging=\(dragging)")
        isDragging = dragging
        dragging ? pendingClose?.cancel() : scheduleCloseIfPointerOutside()
    }

    /// A drag carrying data entered the notch: opens `tab` on purpose and keeps the notch open until the drag ends.
    public func dragEntered(tab: ModuleID?) {
        setHover(.notch)
        open(tab: tab)
        setDragging(true)
    }

    public func dragExited() {
        setDragging(false)
    }

    private func toastDidExpire() {
        toastExpired = true
        if let covered = tabUnderToast {
            // Resolved like any open, so a tab whose module stopped meanwhile falls back to another one.
            show(tab: covered, onPurpose: isOpenedOnPurpose)
            scheduleCloseIfPointerOutside()
        } else if !isPointerInside, !isPinned, !isDragging {
            close()
        }
    }

    private func setHover(_ zone: PointerZone) {
        hover = zone
        isPointerInside = zone != .outside
    }

    private func cancelPendingList() {
        pendingList?.cancel()
        pendingList = nil
    }

    private func hideList() {
        cancelPendingList()
        isListOpen = false
    }

    /// Closes what the pointer left: the open notch, or the list under the collapsed one, after the close delay.
    private func scheduleCloseIfPointerOutside() {
        guard state.isExpanded || isListOpen, !isPointerInside, !isPinned, !isDragging, state != .toast || toastExpired else { return }
        pendingClose?.cancel()
        NotchLog.record("close scheduled")
        pendingClose = scheduler.schedule(after: delays().close) { [weak self] in
            NotchLog.record("close: delay elapsed")
            self?.close()
        }
    }
}

/// The width an activity's strip asked for.
nonisolated struct StripReport: Equatable, Sendable {
    let activity: String
    let width: CGFloat
}
