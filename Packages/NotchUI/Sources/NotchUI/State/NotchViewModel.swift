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
    /// Set by the owner when the activity center has something to show.
    public var hasActivity = false {
        didSet {
            guard hasActivity != oldValue else { return }
            NotchLog.record("activity \(hasActivity) display=\(displayState.logDescription)")
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
    /// The open tab a toast covers; the toast returns to it instead of closing the notch, and the view keeps
    /// it alive underneath so its state (search text, focus, scroll position) survives the toast.
    public private(set) var tabUnderToast: ModuleID?
    /// True when a click, the shortcut, the tab bar or a module opened the notch rather than hovering. Only then
    /// does a keyboard tab take the keyboard by itself.
    public private(set) var isOpenedOnPurpose = false

    /// What the view should render: `closed` becomes `compact` while an activity is live.
    public var displayState: NotchState {
        state == .closed && hasActivity ? .compact : state
    }

    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let availableTabs: () -> [ModuleID]
    @ObservationIgnored private let delays: () -> (open: Duration, close: Duration)
    @ObservationIgnored private var pendingOpen: ScheduledAction?
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

    public func pointerEntered() {
        NotchLog.record("pointer entered state=\(state.logDescription)")
        isPointerInside = true
        pendingClose?.cancel()
        guard !state.isExpanded, pendingOpen == nil else { return }
        pendingOpen = scheduler.schedule(after: delays().open) { [weak self] in
            self?.pendingOpen = nil
            self?.show(tab: nil, onPurpose: false)
        }
    }

    public func pointerExited() {
        NotchLog.record("pointer exited state=\(state.logDescription)")
        isPointerInside = false
        pendingOpen?.cancel()
        pendingOpen = nil
        scheduleCloseIfPointerOutside()
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
        show(tab: tab, onPurpose: true)
    }

    private func show(tab: ModuleID?, onPurpose: Bool) {
        NotchLog.record("show tab=\(tab?.rawValue ?? "-") onPurpose=\(onPurpose) from=\(state.logDescription)")
        pendingOpen?.cancel()
        pendingOpen = nil
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
        guard state.isExpanded, !isPinned, !isDragging else { return }
        NotchLog.record("close: click outside")
        close()
    }

    /// Closes the notch and ends pin and drag mode with it: a closed notch (hidden, toggled shut) must not stay stuck
    /// in drag mode, which would ignore outside clicks and keep a later toast open.
    public func close() {
        NotchLog.record("close from=\(state.logDescription)")
        pendingOpen?.cancel()
        pendingOpen = nil
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
        isPointerInside = true
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

    private func scheduleCloseIfPointerOutside() {
        guard state.isExpanded, !isPointerInside, !isPinned, !isDragging, state != .toast || toastExpired else { return }
        pendingClose?.cancel()
        NotchLog.record("close scheduled")
        pendingClose = scheduler.schedule(after: delays().close) { [weak self] in
            NotchLog.record("close: delay elapsed")
            self?.close()
        }
    }
}
