import MyNotchCore
import Observation
import SwiftUI

/// Per-screen notch state machine. Time is injected through `Scheduler`.
@Observable
public final class NotchViewModel {
    public private(set) var state: NotchState = .closed
    public private(set) var toastContent: AnyView?
    public private(set) var lastTab: ModuleID?
    public private(set) var isPointerInside = false
    /// Set by the owner when the activity center has something to show.
    public var hasActivity = false
    /// Keeps the notch open until unpinned or explicitly closed.
    public var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            isPinned ? pendingClose?.cancel() : scheduleCloseIfPointerOutside()
        }
    }
    public private(set) var isDragging = false

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
        isPointerInside = true
        pendingClose?.cancel()
        guard !state.isExpanded, pendingOpen == nil else { return }
        pendingOpen = scheduler.schedule(after: delays().open) { [weak self] in
            self?.pendingOpen = nil
            self?.open(tab: nil)
        }
    }

    public func pointerExited() {
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

    /// Opens `tab`, or the last used tab, or the first available one.
    public func open(tab: ModuleID?) {
        pendingOpen?.cancel()
        pendingOpen = nil
        pendingClose?.cancel()
        toastTimer?.cancel()
        toastExpired = true
        let tabs = availableTabs()
        let resolved = [tab, lastTab].compactMap { $0 }.first(where: tabs.contains) ?? tabs.first
        lastTab = resolved ?? lastTab
        toastContent = nil
        state = .open(resolved)
    }

    public func showToast(_ content: AnyView, duration: Duration) {
        pendingOpen?.cancel()
        pendingOpen = nil
        pendingClose?.cancel()
        toastTimer?.cancel()
        toastContent = content
        toastExpired = false
        state = .toast
        toastTimer = scheduler.schedule(after: duration) { [weak self] in
            guard let self else { return }
            self.toastExpired = true
            guard !self.isPointerInside, !self.isPinned, !self.isDragging else { return }
            self.close()
        }
    }

    public func close() {
        pendingOpen?.cancel()
        pendingOpen = nil
        pendingClose?.cancel()
        toastTimer?.cancel()
        toastExpired = true
        toastContent = nil
        state = .closed
        isPinned = false
    }

    public func setDragging(_ dragging: Bool) {
        guard dragging != isDragging else { return }
        isDragging = dragging
        dragging ? pendingClose?.cancel() : scheduleCloseIfPointerOutside()
    }

    private func scheduleCloseIfPointerOutside() {
        guard state.isExpanded, !isPointerInside, !isPinned, !isDragging, state != .toast || toastExpired else { return }
        pendingClose?.cancel()
        pendingClose = scheduler.schedule(after: delays().close) { [weak self] in
            self?.close()
        }
    }
}
