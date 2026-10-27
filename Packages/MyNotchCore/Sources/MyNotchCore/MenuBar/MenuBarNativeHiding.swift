import CoreGraphics

/// Which of the hider's sections an app's items are in.
nonisolated public enum MenuBarSection: Comparable, Sendable {
    /// Right of ‹, always shown.
    case visible
    /// Between ‹‹ and ‹ (left of ‹ without a ‹‹).
    case hidden
    /// Left of ‹‹.
    case alwaysHidden

    /// The item reason the bar lists an item of an app in this section with.
    var reason: MenuBarItemReason? {
        switch self {
        case .visible: nil
        case .hidden: .hiddenSection
        case .alwaysHidden: .alwaysHiddenSection
        }
    }
}

/// macOS 27's own restriction of the menu bar to a list of apps (the one assessment mode uses). The app's adapter drives the
/// private framework; tests use a fake.
public protocol MenuBarRestrictionProvider: AnyObject {
    /// Keeps only these apps' items and the system's own on the menu bar, in place of what was kept before. `completion` says
    /// whether it took; one that is lifted or replaced before it took does not count.
    func restrict(toApps allowed: [String], completion: @escaping @MainActor (Bool) -> Void)
    /// Gives every app's items back, at once.
    func lift()
}

/// Hiding on macOS 27 and later, where a long separator no longer pushes anything away: the separators keep their normal
/// length and only mark the sections, and the apps whose items are in a hidden section are taken off the menu bar by the
/// system. The sections are read through Accessibility, by app: an app with items in two sections goes with the more visible.
///
/// While a restriction holds, what the system took away reports where it was before, so an app it hides now keeps the section
/// it was read in; every other app is read again on each change, so what the user ⌘-dragged in between counts. An app that starts
/// while a section is hidden is not on the list and stays away until the next change.
public final class MenuBarNativeHiding {
    /// Whether the system is keeping some apps' items off the menu bar now; their frames say where they were.
    public private(set) var isRestricted = false
    /// The apps taken off the menu bar now, by bundle ID, with the section each was in.
    public private(set) var hiddenApps: [String: MenuBarSection] = [:]
    /// The restriction could not be set: the caller hides some other way.
    public var onFailed: (() -> Void)?
    /// What is hidden changed.
    public var onChanged: (() -> Void)?

    private let provider: any MenuBarRestrictionProvider
    private let source: any MenuBarItemSource
    private let runningApps: () -> [String]
    private let ownBundleID: String
    /// The section each app was last read in.
    private var sections: [String: MenuBarSection] = [:]
    /// Bumped by every change, so a read or a restriction that a later change overtook is dropped.
    private var generation = 0
    private var task: Task<Void, Never>?
    /// The apps the restriction in force keeps.
    private var allowed: [String]?
    /// The restriction is given back for a moment (`suspend()`), what it hides still counting as hidden.
    private var isSuspended = false

    public init(
        provider: any MenuBarRestrictionProvider, source: any MenuBarItemSource, runningApps: @escaping () -> [String], ownBundleID: String
    ) {
        self.provider = provider
        self.source = source
        self.runningApps = runningApps
        self.ownBundleID = ownBundleID
    }

    /// Hides what `level` hides, with the sections read against `layout`'s separators. `.all` gives everything back at once.
    public func apply(_ level: MenuBarHider.Level, layout: @escaping () -> MenuBarLayout) {
        generation += 1
        task?.cancel()
        task = nil
        isSuspended = false
        guard level != .all else {
            lift()
            return
        }
        let mine = generation
        task = Task { [weak self] in
            guard let self else { return }
            let items = await source.items()
            guard mine == generation else { return }
            restrict(for: level, items: items, layout: layout(), generation: mine)
        }
    }

    /// Waits for the read under way (for tests).
    func settled() async {
        await task?.value
    }

    /// Gives the bar back for a moment without forgetting what is hidden, for a click the restriction blocks (the clock opening
    /// Notification Center); `resume()` puts it back. False when nothing is restricted, or it is already given back.
    public func suspend() -> Bool {
        guard isRestricted, !isSuspended, allowed != nil else { return false }
        generation += 1
        task?.cancel()
        task = nil
        isSuspended = true
        provider.lift()
        return true
    }

    /// Puts back what `suspend()` gave back, unless a change since did something else with the bar.
    public func resume() {
        guard isSuspended, let allowed else { return }
        let mine = generation
        provider.restrict(toApps: allowed) { [weak self] took in
            guard let self, mine == generation else { return }
            isSuspended = false
            if !took {
                lift()
                onFailed?()
            }
        }
    }

    private func restrict(for level: MenuBarHider.Level, items: [MenuBarItem], layout: MenuBarLayout, generation mine: Int) {
        let read = Self.sections(of: items, in: layout)
        sections = read.merging(sections.filter { hiddenApps[$0.key] != nil }) { _, kept in kept }
        let hiding: Set<MenuBarSection> = level == .collapsed ? [.hidden, .alwaysHidden] : [.alwaysHidden]
        let running = Set(runningApps())
        let hidden = sections.filter { hiding.contains($0.value) && running.contains($0.key) && $0.key != ownBundleID }
        guard !hidden.isEmpty else {
            lift()
            return
        }
        let allowed = running.union([ownBundleID]).subtracting(hidden.keys).sorted()
        provider.restrict(toApps: allowed) { [weak self] took in
            guard let self, mine == generation else { return }
            guard took else {
                lift()
                onFailed?()
                return
            }
            isRestricted = true
            self.allowed = allowed
            hiddenApps = hidden
            onChanged?()
        }
    }

    private func lift() {
        provider.lift()
        let changed = isRestricted
        isRestricted = false
        isSuspended = false
        allowed = nil
        hiddenApps = [:]
        if changed { onChanged?() }
    }

    /// The section of each app, by bundle ID, from its items' frames against the separators. Items without area, and apps
    /// without a bundle ID, say nothing.
    static func sections(of items: [MenuBarItem], in layout: MenuBarLayout) -> [String: MenuBarSection] {
        var sections: [String: MenuBarSection] = [:]
        for item in items {
            guard let app = item.ownerBundleID, item.frame.width > 0, item.frame.height > 0 else { continue }
            let section = section(of: item.frame, in: layout)
            sections[app] = min(sections[app] ?? section, section)
        }
        return sections
    }

    private static func section(of frame: CGRect, in layout: MenuBarLayout) -> MenuBarSection {
        guard let index = MenuBarOrder.screenIndex(of: frame, in: layout.screens) else { return .visible }
        func isLeft(of separator: CGRect?) -> Bool {
            guard let separator, MenuBarOrder.screenIndex(of: separator, in: layout.screens) == index else { return false }
            return frame.midX < separator.minX
        }
        if isLeft(of: layout.alwaysHiddenSeparator) { return .alwaysHidden }
        if isLeft(of: layout.hiddenSeparator) { return .hidden }
        return .visible
    }
}
