import AppKit

/// App-wide settings of the menu-bar hider (`app.menuBarHider.*`).
public enum MenuBarHiderSettings {
    public static let enabled = SettingKey("app.menuBarHider.enabled", default: false)
    /// Seconds after showing the hidden icons before they hide again; 0 keeps them until the user hides them.
    public static let autoCollapseSeconds = SettingKey("app.menuBarHider.autoCollapseSeconds", default: 10, clampedTo: 0...300)
    /// The pointer on the menu bar shows the hidden icons, and leaving it hides them again.
    public static let revealOnHover = SettingKey("app.menuBarHider.revealOnHover", default: false)
    /// A second separator ‹‹ further left: what is left of it stays hidden when the first one is expanded, and shows only for
    /// an ⌥-click on the MyNotch icon or the menu entry.
    public static let alwaysHiddenSection = SettingKey("app.menuBarHider.alwaysHiddenEnabled", default: false)
    /// Hide when MyNotch starts instead of showing everything until the auto-collapse.
    public static let startCollapsed = SettingKey("app.menuBarHider.startCollapsed", default: false)
    /// The delays the picker offers (seconds, 0 = never). A stored value outside the list is kept and shown as well.
    public static let autoCollapseChoices = [0, 5, 10, 15, 30]
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
    /// Whether the second separator ‹‹ exists, further left than the first; everything below is ignored while it does not.
    var hasAlwaysHiddenSection: Bool { get }
    /// The second separator's length: long while its section is hidden, normal while it is shown.
    var alwaysHiddenLength: CGFloat { get set }
    /// The second separator's window; nil without one. Only meaningful while its length is normal.
    var alwaysHiddenFrame: CGRect? { get }
}

/// Collapsing and expanding the menu bar's sections, by hand, by a timer and by the pointer. Time comes from the injected
/// scheduler. There is one separator ‹ (what is on its left is "hidden") and optionally a second one ‹‹ further left (what
/// is on its left stays "always hidden" until asked for).
public final class MenuBarHider {
    /// How much of the menu bar is shown.
    public enum Level: Equatable, Sendable {
        /// Both zones are off the screen: ‹ and ‹‹ are long.
        case collapsed
        /// The hidden zone shows, the always-hidden zone does not: ‹ is normal, ‹‹ is long.
        case expanded
        /// Both zones show: ‹ and ‹‹ are normal. The same as `expanded` while there is no ‹‹.
        case all
    }

    /// Wider than any display, so the items on the separator's left have no room left on the screen.
    public static let collapsedLength: CGFloat = 10_000
    public static let expandedLength: CGFloat = NSStatusItem.variableLength
    /// How long icons revealed by the pointer stay once it has left the menu bar, so a slip off the edge does not hide them.
    public static let hoverLinger: Duration = .milliseconds(1_500)
    /// How long the windows have to stop moving before the layout is judged: collapsing and expanding move them themselves.
    public static let settleDelay: Duration = .milliseconds(300)
    /// How long after the app started the windows have settled enough to be judged, for "hide at start".
    public static let startDelay: Duration = .milliseconds(1_500)
    /// A start that was refused (the windows were not in place yet) is tried again this much later, `startAttempts` times in all.
    public static let startRetryDelay: Duration = .seconds(2)
    public static let startAttempts = 3
    /// While the pointer is on the menu bar a due auto-collapse waits, looking again this often.
    public static let pointerRecheck: Duration = .seconds(1)

    public private(set) var level: Level = .all
    public var isCollapsed: Bool { level == .collapsed }
    /// Called after the hider showed everything by itself because the MyNotch icon was no longer on the bar.
    public var onForcedExpand: (() -> Void)?

    private let settings: SettingsStore
    private let scheduler: any Scheduler
    /// Whether the pointer is on a menu bar right now. Asked only when an auto-collapse comes due, so nothing watches the mouse.
    private let isPointerOnMenuBar: () -> Bool
    private var separator: (any MenuBarSeparator)?
    /// The timer that collapses: the auto-collapse after a show, the wait for the pointer to leave, or the linger after it left.
    private var pendingCollapse: ScheduledAction?
    /// Shown because the pointer touched the menu bar, so leaving it hides them again; a click or a setting hands over.
    private var revealedByPointer = false
    private var pointerInMenuBar = false
    /// A look at the layout once it has settled, after a window moved while a separator is long.
    private var pendingRevalidate: ScheduledAction?
    /// Right after the user turned the hider on they are placing icons, so nothing collapses by itself until it ends.
    private var graceTimer: ScheduledAction?
    private var isInGrace = false
    /// An auto-collapse came due during the grace and waits for it to end.
    private var collapseDue = false
    /// The state a launch asks for, applied once the windows have settled.
    private var pendingStart: ScheduledAction?

    public init(settings: SettingsStore, scheduler: any Scheduler, isPointerOnMenuBar: @escaping () -> Bool = { false }) {
        self.settings = settings
        self.scheduler = scheduler
        self.isPointerOnMenuBar = isPointerOnMenuBar
    }

    /// Starts with everything shown, so a launch never hides something before the order of the items was judged. With
    /// `quietFor`, nothing collapses by itself until then (a click ends it early), for the time the user spends arranging
    /// icons. With `startingUp`, the start state the settings ask for ("hide at start", the always-hidden zone hidden) is
    /// applied once the windows have settled; it is not when the user has just switched the hider on.
    public func attach(_ separator: any MenuBarSeparator, quietFor grace: Duration = .zero, startingUp: Bool = false) {
        reset()
        self.separator = separator
        separator.length = Self.expandedLength
        if separator.hasAlwaysHiddenSection { separator.alwaysHiddenLength = Self.expandedLength }
        beginGrace(grace)
        scheduleAutoCollapse()
        if startingUp, grace == .zero { scheduleStart(attemptsLeft: Self.startAttempts, after: Self.startDelay) }
    }

    /// Forgets the separator after giving the menu bar back, because the item is about to be removed or replaced.
    public func detach() {
        if let separator {
            separator.length = Self.expandedLength
            if separator.hasAlwaysHiddenSection { separator.alwaysHiddenLength = Self.expandedLength }
        }
        separator = nil
        reset()
    }

    /// ‹‹ appeared or went away. A section that has just appeared is empty and sits at the far left, so everything is shown
    /// (and stays shown for `grace`) for the user to drag icons to its left. One that went away leaves its icons in the hidden zone.
    public func alwaysHiddenSectionChanged(quietFor grace: Duration = .zero) {
        guard let separator else { return }
        if separator.hasAlwaysHiddenSection {
            commit(.all)
            beginGrace(grace)
        } else if !isWide {
            pendingRevalidate?.cancel()
            pendingRevalidate = nil
        }
    }

    /// The menu-bar icon was clicked or the shortcut pressed: from hidden, shows the hidden zone; otherwise hides. False when
    /// there is nothing to toggle or hiding was refused.
    @discardableResult
    public func toggle() -> Bool {
        guard separator != nil else { return false }
        if level == .collapsed {
            expand()
            return true
        }
        return collapse()
    }

    /// The ⌥-click and the menu entry: shows the always-hidden zone too, or, when it shows, puts it away again. Without a ‹‹
    /// it is `toggle()`. False when hiding was refused.
    @discardableResult
    public func toggleAll() -> Bool {
        guard let separator else { return false }
        guard separator.hasAlwaysHiddenSection else { return toggle() }
        if level == .all { return move(to: .expanded) }
        revealAll()
        return true
    }

    /// Shows the hidden zone (the always-hidden one is as it was) and starts the auto-collapse count.
    public func expand() {
        guard separator != nil else { return }
        commit(level == .collapsed ? .expanded : level)
    }

    /// Shows everything, whatever was hidden: for the moments the app goes away, or the way back is in danger.
    public func revealAll() {
        guard separator != nil else { return }
        commit(.all)
    }

    /// Hides both zones. Refused (false) unless the separators are in order on one menu bar (`MenuBarOrder`).
    @discardableResult
    public func collapse() -> Bool {
        guard separator != nil, level != .collapsed else { return false }
        return move(to: .collapsed)
    }

    /// A status-item window moved or the displays changed. While a separator is long, looks again once things have settled
    /// and shows everything if the MyNotch icon is no longer on a menu bar, since that icon is the way back.
    public func layoutChanged() {
        guard separator != nil, isWide else { return }
        pendingRevalidate?.cancel()
        pendingRevalidate = scheduler.schedule(after: Self.settleDelay) { [weak self] in
            self?.pendingRevalidate = nil
            self?.revalidate()
        }
    }

    /// Shows everything when a separator is long and the icon cannot be reached.
    public func revalidate() {
        guard let separator, isWide else { return }
        if let toggle = separator.toggleFrame, MenuBarOrder.isReachable(toggle: toggle, screens: separator.screens) { return }
        revealAll()
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
            pendingCollapse?.cancel()
            pendingCollapse = scheduler.schedule(after: Self.hoverLinger) { [weak self] in
                self?.pendingCollapse = nil
                self?.collapse()
            }
        }
    }

    // MARK: transitions

    /// Whether a separator is long now, so the MyNotch icon could be pushed off the screen if the order were wrong.
    private var isWide: Bool {
        level == .collapsed || (level == .expanded && separator?.hasAlwaysHiddenSection == true)
    }

    /// A change the user, a timer or the pointer asked for. Refused when it would make a separator long without the order of
    /// the items having been confirmed. Moving to `target` already is a success.
    private func move(to target: Level) -> Bool {
        guard separator != nil else { return false }
        guard target != level else { return true }
        guard isInOrder(for: target) else { return false }
        commit(target)
        return true
    }

    /// The order is judged from the windows' frames while the separator in question has its normal length: a long one's
    /// window is 10 000 points wide and its frame says nothing. ‹ must end before the icon's middle; ‹‹ before ‹.
    private func isInOrder(for target: Level) -> Bool {
        guard let separator else { return false }
        let wideningHidden = target == .collapsed && level != .collapsed
        let wideningAlways = separator.hasAlwaysHiddenSection && target != .all && level == .all
        guard wideningHidden || wideningAlways else { return true }
        let screens = separator.screens
        guard let own = separator.separatorFrame, let toggle = separator.toggleFrame,
              MenuBarOrder.isLeftOf(separator: own, toggle: toggle, screens: screens) else { return false }
        guard wideningAlways else { return true }
        guard let always = separator.alwaysHiddenFrame else { return false }
        return MenuBarOrder.isLeftOf(separator: always, toggle: own, screens: screens)
    }

    /// Takes `target`, and restarts what follows from it: the auto-collapse count; the user's choice wins over a pending start.
    private func commit(_ target: Level) {
        endGrace()
        pendingStart?.cancel()
        pendingStart = nil
        pendingCollapse?.cancel()
        pendingCollapse = nil
        revealedByPointer = false
        setLevel(target)
        if !isWide {
            pendingRevalidate?.cancel()
            pendingRevalidate = nil
        }
        scheduleAutoCollapse()
    }

    /// Sets the lengths of the separators that change, and nothing else.
    private func setLevel(_ target: Level) {
        guard let separator, target != level else { return }
        if (target == .collapsed) != (level == .collapsed) {
            separator.length = target == .collapsed ? Self.collapsedLength : Self.expandedLength
        }
        if separator.hasAlwaysHiddenSection, (target != .all) != (level != .all) {
            separator.alwaysHiddenLength = target == .all ? Self.expandedLength : Self.collapsedLength
        }
        level = target
    }

    private func revealByPointer() {
        setLevel(.expanded)
        revealedByPointer = true
    }

    // MARK: timers

    private func scheduleAutoCollapse() {
        let seconds = settings.value(MenuBarHiderSettings.autoCollapseSeconds)
        pendingCollapse?.cancel()
        pendingCollapse = nil
        guard !isCollapsed, seconds > 0 else { return }
        pendingCollapse = scheduler.schedule(after: .seconds(seconds)) { [weak self] in self?.autoCollapseDue() }
    }

    private func autoCollapseDue() {
        pendingCollapse = nil
        guard !isInGrace else {
            collapseDue = true
            return
        }
        if isPointerOnMenuBar() { waitForPointerToLeave() } else { collapse() }
    }

    /// The icons stay while the pointer is on the menu bar (it may be on its way to one); once it is away, the count starts again.
    private func waitForPointerToLeave() {
        pendingCollapse = scheduler.schedule(after: Self.pointerRecheck) { [weak self] in
            guard let self else { return }
            pendingCollapse = nil
            if isPointerOnMenuBar() { waitForPointerToLeave() } else { scheduleAutoCollapse() }
        }
    }

    private func graceEnded() {
        graceTimer = nil
        isInGrace = false
        guard collapseDue else { return }
        collapseDue = false
        pendingCollapse?.cancel()
        autoCollapseDue()
    }

    private func beginGrace(_ grace: Duration) {
        guard grace > .zero else { return }
        isInGrace = true
        graceTimer = scheduler.schedule(after: grace) { [weak self] in self?.graceEnded() }
    }

    private func endGrace() {
        graceTimer?.cancel()
        graceTimer = nil
        isInGrace = false
        collapseDue = false
    }

    /// What a launch asks for, if anything: hidden, or just the always-hidden zone away.
    private var startTarget: Level? {
        if settings.value(MenuBarHiderSettings.startCollapsed) { return .collapsed }
        return separator?.hasAlwaysHiddenSection == true ? .expanded : nil
    }

    private func scheduleStart(attemptsLeft: Int, after delay: Duration) {
        guard let target = startTarget else { return }
        pendingStart = scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            pendingStart = nil
            if !move(to: target), attemptsLeft > 1 { scheduleStart(attemptsLeft: attemptsLeft - 1, after: Self.startRetryDelay) }
        }
    }

    private func reset() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingRevalidate?.cancel()
        pendingRevalidate = nil
        pendingStart?.cancel()
        pendingStart = nil
        endGrace()
        level = .all
        revealedByPointer = false
    }
}
