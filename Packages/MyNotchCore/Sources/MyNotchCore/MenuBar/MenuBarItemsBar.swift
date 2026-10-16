import CoreGraphics
import Observation

/// The bar under the menu bar that holds the icons the notch hides: what it lists, when it is read again, when it closes, and
/// what a click on an item does. It never touches the menu bar itself: the apps' items, their looks and the hider's sections
/// come in through the three protocols, and time through the scheduler.
///
/// Nothing runs while the bar is closed: an event that arrives then is ignored, and the items are read again on every opening.
@Observable
public final class MenuBarItemsBar {
    public enum Phase: Equatable, Sendable {
        /// Opened, and the first list has not arrived.
        case loading
        /// Accessibility is not granted, so there is nothing to list.
        case needsAccessibility
        case ready
    }

    public enum CloseReason: Equatable, Sendable {
        /// The icon, ‹ or the shortcut asked for it.
        case toggle
        case clickOutside
        case escape
        case itemChosen
        /// The auto-collapse time.
        case timeout
        /// The hider was switched off, the setting turned off, or the MyNotch icon went away.
        case unavailable
    }

    /// Events (an app started or quit, the sections moved, a display changed) come in bursts: the list is read once they stop.
    public static let refreshDelay: Duration = .milliseconds(250)
    /// While the pointer is on the bar a due close waits, looking again this often.
    public static let pointerRecheck: Duration = .seconds(1)
    /// After the sections were shown for an item, how often to look whether it has arrived on the bar, and how many looks to give it.
    public static let revealPoll: Duration = .milliseconds(100)
    public static let revealPolls = 6
    /// How long after the last press the sections stay shown before they go back.
    public static let restoreDelay: Duration = .seconds(5)

    public private(set) var isOpen = false
    public private(set) var phase = Phase.loading
    /// What the bar holds, left to right.
    public private(set) var entries: [MenuBarBarEntry] = []
    /// How the items really look, by item ID. Best effort: an item without one is shown as its app's icon. Held only while open.
    public private(set) var images: [String: CGImage] = [:]
    public private(set) var lastCloseReason: CloseReason?

    /// The window follows: open or closed.
    @ObservationIgnored public var onOpenChanged: ((Bool) -> Void)?
    /// An item could not be opened through Accessibility.
    @ObservationIgnored public var onPressFailed: (() -> Void)?

    @ObservationIgnored private let source: any MenuBarItemSource
    @ObservationIgnored private let imageSource: (any MenuBarItemImageSource)?
    @ObservationIgnored private let sections: any MenuBarSectionControl
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let layout: () -> MenuBarLayout
    @ObservationIgnored private let isPointerOnBar: () -> Bool

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: ScheduledAction?
    @ObservationIgnored private var autoClose: ScheduledAction?
    /// The wait for an item to arrive on the bar after the sections were shown for it.
    @ObservationIgnored private var pendingPerform: ScheduledAction?
    @ObservationIgnored private var pendingRestore: ScheduledAction?
    /// The level the hider was at before the sections were shown for an item, which they go back to.
    @ObservationIgnored private var restoreTarget: MenuBarHider.Level?

    public init(
        source: any MenuBarItemSource, images: (any MenuBarItemImageSource)? = nil, sections: any MenuBarSectionControl,
        settings: SettingsStore, scheduler: any Scheduler, layout: @escaping () -> MenuBarLayout,
        isPointerOnBar: @escaping () -> Bool = { false }
    ) {
        self.source = source
        self.imageSource = images
        self.sections = sections
        self.settings = settings
        self.scheduler = scheduler
        self.layout = layout
        self.isPointerOnBar = isPointerOnBar
    }

    /// The bar takes the place of showing the hidden section in the menu bar only with the hider and the setting on, and when
    /// Accessibility lets it list the items; without that, a click keeps doing what it did.
    public static func isAvailable(hiderOn: Bool, settingOn: Bool, accessibilityGranted: Bool) -> Bool {
        hiderOn && settingOn && accessibilityGranted
    }

    // MARK: opening and closing

    public func toggle() {
        if isOpen { close(.toggle) } else { open() }
    }

    /// Opens the bar and reads the items.
    public func open() {
        guard !isOpen else { return }
        isOpen = true
        phase = .loading
        entries = []
        images = [:]
        lastCloseReason = nil
        onOpenChanged?(true)
        startRefresh()
        scheduleAutoClose()
    }

    public func close(_ reason: CloseReason) {
        guard isOpen else { return }
        isOpen = false
        lastCloseReason = reason
        autoClose?.cancel()
        autoClose = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        generation += 1
        refreshTask?.cancel()
        entries = []
        images = [:]
        onOpenChanged?(false)
    }

    /// Call after the auto-collapse time changed, so what is pending follows it.
    public func settingsChanged() {
        guard isOpen else { return }
        scheduleAutoClose()
    }

    // MARK: events

    /// An app started or quit, the hider moved a section, or a display changed. Reads the items again once the events stop; a
    /// closed bar ignores them, since it reads them anew when it opens.
    public func itemsMayHaveChanged() {
        guard isOpen else { return }
        pendingRefresh?.cancel()
        pendingRefresh = scheduler.schedule(after: Self.refreshDelay) { [weak self] in
            self?.pendingRefresh = nil
            self?.startRefresh()
        }
    }

    /// Waits for the read that is under way (for tests).
    func settled() async {
        await refreshTask?.value
    }

    private func startRefresh() {
        generation += 1
        let mine = generation
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.refresh(generation: mine) }
    }

    private func refresh(generation mine: Int) async {
        guard isOpen, mine == generation else { return }
        guard source.isTrusted else {
            phase = .needsAccessibility
            entries = []
            images = [:]
            return
        }
        let items = await source.items()
        guard isOpen, mine == generation else { return }
        let list = MenuBarReachability.entries(from: items, layout: layout())
        entries = list
        phase = .ready
        images = images.filter { image in list.contains { $0.id == image.key } }
        guard let imageSource, !list.isEmpty else { return }
        let captured = await imageSource.images(for: list.map(\.item))
        guard isOpen, mine == generation else { return }
        images = captured
    }

    // MARK: auto-close

    private func scheduleAutoClose() {
        autoClose?.cancel()
        autoClose = nil
        let seconds = settings.value(MenuBarHiderSettings.autoCollapseSeconds)
        guard isOpen, seconds > 0 else { return }
        autoClose = scheduler.schedule(after: .seconds(seconds)) { [weak self] in self?.autoCloseDue() }
    }

    private func autoCloseDue() {
        autoClose = nil
        if isPointerOnBar() { waitForPointerToLeave() } else { close(.timeout) }
    }

    /// The bar stays while the pointer is on it (it may be on its way to an item); once it is away, the count starts again.
    private func waitForPointerToLeave() {
        autoClose = scheduler.schedule(after: Self.pointerRecheck) { [weak self] in
            guard let self else { return }
            autoClose = nil
            if isPointerOnBar() { waitForPointerToLeave() } else { scheduleAutoClose() }
        }
    }

    // MARK: choosing an item

    /// A click on an item (`secondary`: a right-click). The bar closes first, so nothing of it is in the way of the menu that opens.
    public func choose(_ id: String, secondary: Bool = false) {
        guard isOpen, let entry = entries.first(where: { $0.id == id }) else { return }
        close(.itemChosen)
        let chain: [MenuBarItemAction] = secondary ? [.showMenu, .press] : [.press, .showMenu]
        guard needsReveal(entry) else {
            press(chain, on: id)
            return
        }
        if restoreTarget == nil { restoreTarget = sections.level }
        sections.revealAll()
        waitForItem(id, chain, attempt: 1)
    }

    /// Whether the item has to be brought back on the bar before it is pressed: it is where the separators put it, off the screen,
    /// and the sections are not all shown. What no separator moves (behind the notch, no window) is pressed where it is, and so is an
    /// item that can be clicked right now, whatever the list said a moment ago.
    private func needsReveal(_ entry: MenuBarBarEntry) -> Bool {
        switch entry.reason {
        case .underNotch, .zeroSize:
            return false
        case .offScreen, .hiddenSection, .alwaysHiddenSection:
            guard sections.level != .all else { return false }
            if let frame = source.currentFrame(of: entry.id), MenuBarReachability.isClickable(frame, in: layout().screens) { return false }
            return true
        }
    }

    /// The windows move a moment after a section is shown: look every `revealPoll` for the item on the bar, and press it where it is
    /// after the last look, which is all that can be done for an item that does not come.
    private func waitForItem(_ id: String, _ chain: [MenuBarItemAction], attempt: Int) {
        pendingPerform = scheduler.schedule(after: Self.revealPoll) { [weak self] in
            guard let self else { return }
            pendingPerform = nil
            let arrived = source.currentFrame(of: id).map { MenuBarReachability.isClickable($0, in: layout().screens) } ?? false
            if arrived || attempt >= Self.revealPolls {
                press(chain, on: id)
            } else {
                waitForItem(id, chain, attempt: attempt + 1)
            }
        }
    }

    /// Tries the actions in turn: the next one only when an item does not have the one before. Whatever follows a refusal that is not
    /// that (a failed call) is not tried, since an item that opened its menu once must not open it twice.
    private func press(_ chain: [MenuBarItemAction], on id: String) {
        if !run(chain, on: id) { onPressFailed?() }
        if restoreTarget != nil { scheduleRestore() }
    }

    private func run(_ chain: [MenuBarItemAction], on id: String) -> Bool {
        for action in chain {
            switch source.perform(action, on: id) {
            case .performed: return true
            case .unsupported: continue
            case .failed: return false
            }
        }
        return false
    }

    /// The sections go back to what they were once the press is a while behind, unless the user has moved them since.
    private func scheduleRestore() {
        pendingRestore?.cancel()
        pendingRestore = scheduler.schedule(after: Self.restoreDelay) { [weak self] in
            guard let self else { return }
            pendingRestore = nil
            let target = restoreTarget
            restoreTarget = nil
            if let target, sections.level == .all { sections.restore(to: target) }
        }
    }
}

extension MenuBarHider: MenuBarSectionControl {}
