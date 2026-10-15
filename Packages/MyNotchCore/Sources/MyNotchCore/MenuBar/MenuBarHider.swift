import AppKit

/// App-wide settings of the menu-bar hider (`app.menuBarHider.*`).
public enum MenuBarHiderSettings {
    public static let enabled = SettingKey("app.menuBarHider.enabled", default: false)
    /// Seconds after showing the hidden icons before they hide again; 0 keeps them until the user hides them.
    public static let autoCollapseSeconds = SettingKey("app.menuBarHider.autoCollapseSeconds", default: 10, clampedTo: 0...300)
    /// The pointer on the menu bar shows the hidden icons, and leaving it hides them again.
    public static let revealOnHover = SettingKey("app.menuBarHider.revealOnHover", default: false)
}

/// The status item that splits the menu bar: whatever the user ⌘-drags to its left is hidden while it is collapsed.
/// The app's adapter wraps the real `NSStatusItem`, so the logic here never touches the menu bar.
public protocol MenuBarSeparator: AnyObject {
    /// The status item's length. A huge one pushes the icons on its left off the edge of the screen.
    var length: CGFloat { get set }
    /// The separator's window in screen coordinates; nil without one.
    var separatorFrame: CGRect? { get }
    /// The window of the MyNotch icon, which toggles the separator; nil without one. If it is hidden or off the screen, so is
    /// the way back.
    var toggleFrame: CGRect? { get }
    /// The menu bars of the displays the frames are judged against (`MenuBarOrder`).
    var screens: [MenuBarScreen] { get }
}

/// Collapsing and expanding the menu-bar separator, by hand, by a timer and by the pointer. Time comes from the
/// injected scheduler.
public final class MenuBarHider {
    /// Wider than any display, so the items on the separator's left have no room left on the screen.
    public static let collapsedLength: CGFloat = 10_000
    public static let expandedLength: CGFloat = NSStatusItem.variableLength
    /// How long icons revealed by the pointer stay once it has left the menu bar, so a slip off the edge does not hide them.
    public static let hoverLinger: Duration = .milliseconds(1_500)
    /// How long the windows have to stop moving before the layout is judged: collapsing and expanding move them themselves.
    public static let settleDelay: Duration = .milliseconds(300)

    public private(set) var isCollapsed = false
    /// Called after the hider expanded by itself because the MyNotch icon was no longer on the bar.
    public var onForcedExpand: (() -> Void)?

    private let settings: SettingsStore
    private let scheduler: any Scheduler
    private var separator: (any MenuBarSeparator)?
    /// The timer that collapses: the auto-collapse after a show, or the linger after the pointer left.
    private var pendingCollapse: ScheduledAction?
    /// Shown because the pointer touched the menu bar, so leaving it hides them again; a click or a setting hands over.
    private var revealedByPointer = false
    private var pointerInMenuBar = false
    /// A look at the layout once it has settled, after a window moved while collapsed.
    private var pendingRevalidate: ScheduledAction?
    /// Right after the user turned the hider on they are placing icons, so nothing collapses by itself until it ends.
    private var graceTimer: ScheduledAction?
    private var isInGrace = false
    /// An auto-collapse came due during the grace and waits for it to end.
    private var collapseDue = false

    public init(settings: SettingsStore, scheduler: any Scheduler) {
        self.settings = settings
        self.scheduler = scheduler
    }

    /// Starts with everything shown, so a launch never hides something before the user chose to. With `quietFor`, nothing
    /// collapses by itself until then (a click ends it early), for the time the user spends arranging icons.
    public func attach(_ separator: any MenuBarSeparator, quietFor grace: Duration = .zero) {
        reset()
        self.separator = separator
        separator.length = Self.expandedLength
        if grace > .zero {
            isInGrace = true
            graceTimer = scheduler.schedule(after: grace) { [weak self] in self?.graceEnded() }
        }
        scheduleAutoCollapse()
    }

    /// Forgets the separator after giving the menu bar back, because the item is about to be removed or replaced.
    public func detach() {
        separator?.length = Self.expandedLength
        separator = nil
        reset()
    }

    /// The menu-bar icon was clicked or the shortcut pressed. False when there is nothing to toggle or hiding was refused.
    @discardableResult
    public func toggle() -> Bool {
        guard separator != nil else { return false }
        if isCollapsed {
            expand()
            return true
        }
        return collapse()
    }

    /// Shows the hidden icons and starts the auto-collapse count.
    public func expand() {
        guard let separator else { return }
        endGrace()
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingRevalidate?.cancel()
        pendingRevalidate = nil
        revealedByPointer = false
        if isCollapsed {
            separator.length = Self.expandedLength
            isCollapsed = false
        }
        scheduleAutoCollapse()
    }

    /// Hides them. Refused (false) unless "‹" is left of the MyNotch icon on one menu bar (`MenuBarOrder`).
    @discardableResult
    public func collapse() -> Bool {
        guard let separator, !isCollapsed else { return false }
        guard let own = separator.separatorFrame, let toggle = separator.toggleFrame,
              MenuBarOrder.isLeftOf(separator: own, toggle: toggle, screens: separator.screens) else { return false }
        endGrace()
        pendingCollapse?.cancel()
        pendingCollapse = nil
        revealedByPointer = false
        separator.length = Self.collapsedLength
        isCollapsed = true
        return true
    }

    /// A status-item window moved or the displays changed. While collapsed, looks again once things have settled and shows
    /// everything if the MyNotch icon is no longer on a menu bar, since that icon is the way back.
    public func layoutChanged() {
        guard separator != nil, isCollapsed else { return }
        pendingRevalidate?.cancel()
        pendingRevalidate = scheduler.schedule(after: Self.settleDelay) { [weak self] in
            self?.pendingRevalidate = nil
            self?.revalidate()
        }
    }

    /// Expands when collapsed and the icon cannot be reached.
    public func revalidate() {
        guard let separator, isCollapsed else { return }
        if let toggle = separator.toggleFrame, MenuBarOrder.isReachable(toggle: toggle, screens: separator.screens) { return }
        expand()
        onForcedExpand?()
    }

    /// Call after the delay or the hover setting changed, so what is pending follows it.
    public func settingsChanged() {
        guard separator != nil, !isCollapsed else { return }
        if revealedByPointer {
            guard !settings.value(MenuBarHiderSettings.revealOnHover) else { return }
            revealedByPointer = false
        }
        scheduleAutoCollapse()
    }

    /// Whether the pointer is on a menu bar now; only a change matters. With "reveal on hover" on, arriving shows the
    /// hidden icons and leaving hides them after a moment.
    public func pointerMoved(inMenuBar inside: Bool) {
        guard inside != pointerInMenuBar else { return }
        pointerInMenuBar = inside
        guard separator != nil, settings.value(MenuBarHiderSettings.revealOnHover) else { return }
        if inside {
            if isCollapsed {
                revealByPointer()
            } else if revealedByPointer {
                pendingCollapse?.cancel()
                pendingCollapse = nil
            }
        } else if revealedByPointer, !isCollapsed {
            scheduleCollapse(after: Self.hoverLinger)
        }
    }

    private func revealByPointer() {
        guard let separator else { return }
        separator.length = Self.expandedLength
        isCollapsed = false
        revealedByPointer = true
    }

    private func scheduleAutoCollapse() {
        let seconds = settings.value(MenuBarHiderSettings.autoCollapseSeconds)
        pendingCollapse?.cancel()
        pendingCollapse = nil
        guard !isCollapsed, seconds > 0 else { return }
        scheduleCollapse(after: .seconds(seconds))
    }

    private func scheduleCollapse(after delay: Duration) {
        pendingCollapse?.cancel()
        pendingCollapse = scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            pendingCollapse = nil
            if isInGrace { collapseDue = true } else { collapse() }
        }
    }

    private func graceEnded() {
        graceTimer = nil
        isInGrace = false
        guard collapseDue else { return }
        collapseDue = false
        collapse()
    }

    private func endGrace() {
        graceTimer?.cancel()
        graceTimer = nil
        isInGrace = false
        collapseDue = false
    }

    private func reset() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingRevalidate?.cancel()
        pendingRevalidate = nil
        endGrace()
        isCollapsed = false
        revealedByPointer = false
    }
}
