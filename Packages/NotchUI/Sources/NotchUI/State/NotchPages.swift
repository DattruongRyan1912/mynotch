import MyNotchCore

/// The pages of the open notch as the tab bar shows them: the pages on the bar, then one "Khác" item that stands for all the others. Pure
/// lists of ids, so what the bar, the swipe and the model make of them is checked without a view.
///
/// "Khác" is a page of its own as far as the notch is concerned (`moreID`): opening it shows the grid of the pages in it. Opening one of
/// those pages shows that page, and the bar still marks "Khác" as selected, with that page's icon on it.
nonisolated struct NotchPages: Equatable, Sendable {
    /// The id the "Khác" item and its grid go by in the notch's state. Not a module's: a module's is never this.
    static let moreID: ModuleID = "khac"

    /// The pages on the bar, in order.
    var bar: [ModuleID]
    /// The pages in Khác, in order.
    var overflow: [ModuleID]

    /// There is a Khác item only while it has a page to hold.
    var hasMore: Bool { !overflow.isEmpty }

    /// The items of the tab bar, in order: the pages on it, then Khác.
    var items: [ModuleID] { bar + (hasMore ? [Self.moreID] : []) }

    /// Everything that can be opened: the bar's pages, Khác and the pages in it. The first is what an open with no page in mind shows.
    var selectable: [ModuleID] { bar + (hasMore ? [Self.moreID] + overflow : []) }

    /// How many pages there are, which tells whether there is a tab bar at all (two or more).
    var count: Int { bar.count + overflow.count }

    func isOverflow(_ page: ModuleID) -> Bool { overflow.contains(page) }

    /// What the bar marks while `shown` is open: the item that shows it as selected, and for a page in Khác that page, which is the badge on
    /// the "Khác" item so the user knows where they are. None for the grid of Khác itself, which is what the item is.
    func selection(of shown: ModuleID?) -> (item: ModuleID?, badge: ModuleID?) {
        guard let shown else { return (nil, nil) }
        return (item(of: shown), isOverflow(shown) ? shown : nil)
    }

    /// The item of the bar that shows `page` as selected: the page itself, or Khác for a page in it and for its grid.
    func item(of page: ModuleID) -> ModuleID {
        page == Self.moreID || isOverflow(page) ? Self.moreID : page
    }
}

extension ModuleRegistry {
    /// The pages as the bar shows them now. Reads the settings, so a view that reads it follows a change of the order or the placement.
    var pages: NotchPages {
        // A single page has nothing to be grouped with, and no tab bar to hold a "Khác" item: it is simply the page.
        if tabs.count == 1 { return NotchPages(bar: tabs.map(\.id), overflow: []) }
        return NotchPages(bar: barTabs.map(\.id), overflow: overflowTabs.map(\.id))
    }
}
