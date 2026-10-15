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
    /// Whether it sits left of the icon that toggles it. Collapsing with the separator on its right would push the
    /// toggle off the screen as well, and with it the way back.
    var isLeftOfToggle: Bool { get }
}

/// Collapsing and expanding the menu-bar separator, by hand, by a timer and by the pointer. Time comes from the
/// injected scheduler.
public final class MenuBarHider {
    /// Wider than any display, so the items on the separator's left have no room left on the screen.
    public static let collapsedLength: CGFloat = 10_000
    public static let expandedLength: CGFloat = NSStatusItem.variableLength
    /// How long icons revealed by the pointer stay once it has left the menu bar, so a slip off the edge does not hide them.
    public static let hoverLinger: Duration = .milliseconds(1_500)

    public private(set) var isCollapsed = false

    private let settings: SettingsStore
    private let scheduler: any Scheduler
    private var separator: (any MenuBarSeparator)?
    /// The timer that collapses: the auto-collapse after a show, or the linger after the pointer left.
    private var pendingCollapse: ScheduledAction?
    /// Shown because the pointer touched the menu bar, so leaving it hides them again; a click or a setting hands over.
    private var revealedByPointer = false
    private var pointerInMenuBar = false

    public init(settings: SettingsStore, scheduler: any Scheduler) {
        self.settings = settings
        self.scheduler = scheduler
    }

    /// Starts with everything shown, so a launch never hides something before the user chose to.
    public func attach(_ separator: any MenuBarSeparator) {
        reset()
        self.separator = separator
        separator.length = Self.expandedLength
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
        pendingCollapse?.cancel()
        pendingCollapse = nil
        revealedByPointer = false
        if isCollapsed {
            separator.length = Self.expandedLength
            isCollapsed = false
        }
        scheduleAutoCollapse()
    }

    /// Hides them. Refused (false) while the separator is not left of the icon that brings them back.
    @discardableResult
    public func collapse() -> Bool {
        guard let separator, !isCollapsed else { return false }
        guard separator.isLeftOfToggle else { return false }
        pendingCollapse?.cancel()
        pendingCollapse = nil
        revealedByPointer = false
        separator.length = Self.collapsedLength
        isCollapsed = true
        return true
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
            self?.pendingCollapse = nil
            self?.collapse()
        }
    }

    private func reset() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        isCollapsed = false
        revealedByPointer = false
    }
}
