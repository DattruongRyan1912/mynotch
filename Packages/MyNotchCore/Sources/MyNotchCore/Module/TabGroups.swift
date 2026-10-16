/// Where each page of the open notch is: on the tab bar, or in the "Khác" item that holds the less used ones. Plain list arithmetic like
/// `TabOrder`, so the rules (the defaults, what a new module does, what the arrangement of the Settings page stores) are checked without a
/// registry.
///
/// What is stored is `app.tabOverflow` (`ModuleRegistry.tabOverflowKey`): the ids in Khác, or nothing at all (never set), which is not the
/// same as an empty list (the user emptied Khác). Beside it is the order of every page (`app.tabOrder`), which also tells a page the user has
/// placed from one nobody has seen.
nonisolated public enum TabGroups {
    /// The pages that are on the bar until the user says otherwise: the ones used most. Every other page, and every module added later, is in
    /// Khác until the user says otherwise.
    public static let defaultBar: [ModuleID] = ["clipboard", "media", "translation", "aiagents", "calendar", "todo"]

    /// Which of `available` are in Khác.
    ///
    /// * Never set (`stored` nil): the defaults, for every page, whatever order was stored before: everything that is not in `defaultBar`.
    /// * Set: the stored ids; and a page the arrangement has never seen (in neither `stored` nor `order`, say a module that was off, or
    ///   one that was added later) takes its default: on the bar if it is in `defaultBar`, else in Khác.
    public static func overflow(stored: [ModuleID]?, order: [ModuleID], available: [ModuleID]) -> Set<ModuleID> {
        guard let stored else { return Set(available.filter { !defaultBar.contains($0) }) }
        let placed = Set(stored).union(order)
        return Set(available.filter { stored.contains($0) || (!placed.contains($0) && !defaultBar.contains($0)) })
    }

    /// `ordered` (all the pages, in the user's order) split into the bar and Khác, each keeping that order.
    public static func split(ordered: [ModuleID], overflow: Set<ModuleID>) -> Arrangement {
        Arrangement(bar: ordered.filter { !overflow.contains($0) }, overflow: ordered.filter(overflow.contains))
    }

    /// The pages as they are on the bar and in Khác, as the Settings page shows them.
    public struct Arrangement: Equatable, Sendable {
        public var bar: [ModuleID]
        public var overflow: [ModuleID]

        public init(bar: [ModuleID], overflow: [ModuleID]) {
            self.bar = bar
            self.overflow = overflow
        }
    }

    public enum Side: Equatable, Sendable {
        case bar, overflow
    }

    /// `page` moved to `side` at `index` (counted in that side as it is without `page`; held to its length). Anywhere else nothing
    /// changes, and a page that is not in the arrangement is not added.
    public static func moving(_ page: ModuleID, to side: Side, at index: Int, in arrangement: Arrangement) -> Arrangement {
        guard arrangement.bar.contains(page) || arrangement.overflow.contains(page) else { return arrangement }
        var moved = Arrangement(bar: arrangement.bar.filter { $0 != page }, overflow: arrangement.overflow.filter { $0 != page })
        switch side {
        case .bar: moved.bar.insert(page, at: min(max(index, 0), moved.bar.count))
        case .overflow: moved.overflow.insert(page, at: min(max(index, 0), moved.overflow.count))
        }
        return moved
    }

    /// `page` dropped on the row of `target`: it goes to the side `target` is on, just before it, whichever way it came (from above or below it
    /// in the same section, or from the other one). Dropped on itself, or with a page or a target that is not there, nothing changes.
    public static func moving(_ page: ModuleID, before target: ModuleID, in arrangement: Arrangement) -> Arrangement {
        let everyone = arrangement.bar + arrangement.overflow
        guard page != target, everyone.contains(page), everyone.contains(target) else { return arrangement }
        let side: Side = arrangement.bar.contains(target) ? .bar : .overflow
        // The place is counted in the section without `page`, which is where `moving(_:to:at:in:)` counts it.
        let remaining = (side == .bar ? arrangement.bar : arrangement.overflow).filter { $0 != page }
        return moving(page, to: side, at: remaining.firstIndex(of: target) ?? remaining.count, in: arrangement)
    }

    /// What to store once the user arranged the pages on screen as `visible`: the order of every page (the bar's, then Khác's, with what is
    /// stored but not on screen after them, as `TabOrder.updated`), and the ids in Khác: those on screen, and those that were in Khác but
    /// are not on screen (a module that is off), so they find their place again. A module that is off and was never placed keeps its
    /// default: it is added to Khác if that is its default.
    public static func stored(
        for visible: Arrangement, order: [ModuleID], overflow stored: [ModuleID]?
    ) -> (order: [ModuleID], overflow: [ModuleID]) {
        let shown = Set(visible.bar + visible.overflow)
        let before = stored ?? (order + visible.bar + visible.overflow).filter { !defaultBar.contains($0) }
        var seen: Set<ModuleID> = []
        let overflow = (visible.overflow + before.filter { !shown.contains($0) }).filter { seen.insert($0).inserted }
        return (TabOrder.updated(stored: order, visible: visible.bar + visible.overflow), overflow)
    }
}
