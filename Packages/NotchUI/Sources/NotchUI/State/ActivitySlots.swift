import MyNotchCore

/// One bubble beside the collapsed notch, or one row of the list: an activity, or the "+N" that stands for the
/// activities that do not fit.
enum ActivitySlot: Identifiable, Equatable {
    case activity(ActivityCenter.Entry)
    case overflow(Int)

    /// A bubble keeps its identity while its number changes, so "+3" turning into "+4" is not a new bubble.
    var id: String {
        switch self {
        case .activity(let entry): entry.id
        case .overflow: "+more"
        }
    }

    /// `items` in `capacity` slots: all of them when they fit, else the first `capacity - 1` and one "+N" slot for the
    /// rest. `extra` counts activities that are not in `items` but still live (past `ActivityCenter`'s cap).
    static func fit(_ items: [ActivityCenter.Entry], extra: Int = 0, capacity: Int) -> [ActivitySlot] {
        let total = items.count + extra
        guard capacity > 0, total > 0 else { return [] }
        if extra == 0, total <= capacity { return items.map(ActivitySlot.activity) }
        let kept = items.prefix(capacity - 1)
        return kept.map(ActivitySlot.activity) + [.overflow(total - kept.count)]
    }

    /// The bubbles for what is live besides the primary activity. At most `capacity` of them, the last one "+N" when
    /// there are more activities than that (the primary does not count).
    static func bubbles(of activities: some ActivityFeed, capacity: Int) -> [ActivitySlot] {
        fit(activities.others, extra: activities.hiddenCount, capacity: capacity)
    }

    /// The rows of the list: every live activity, the primary first.
    static func listRows(of activities: some ActivityFeed, capacity: Int) -> [ActivitySlot] {
        fit(activities.ordered, capacity: capacity)
    }
}

/// What hangs off the collapsed notch right now: the bubbles beside it and the rows of the list under it. The view and
/// the window controller both read this one value, so what is drawn and what the pointer can hit cannot disagree.
struct CompactAccessories: Equatable {
    /// Bubbles drawn beside the pill (0...`maxBubbles`).
    var bubbles = 0
    /// Rows of the open list; 0 while it is closed.
    var listRows = 0

    static let none = CompactAccessories()

    init(bubbles: Int = 0, listRows: Int = 0) {
        self.bubbles = bubbles
        self.listRows = listRows
    }

    /// Nothing while the notch is not collapsed with an activity; otherwise as many bubbles as there are other
    /// activities and the panel holds, and the open list's rows when there is a bubble to hover.
    init(activities: some ActivityFeed, geometry: NotchGeometry, isListOpen: Bool, state: NotchState) {
        guard state == .compact else { self = .none; return }
        let bubbles = Self.bubbleCount(activities: activities, geometry: geometry)
        self.init(bubbles: bubbles, listRows: isListOpen && bubbles > 0 ? min(activities.ordered.count, NotchGeometry.maxListRows) : 0)
    }

    /// How many bubbles `activities` has beside the notch, whatever the notch is doing: what the view model needs to
    /// know to open a list at all. `others` is capped at three and never holds the primary, so this does not read
    /// `ordered`, which changes with every update of any activity.
    static func bubbleCount(activities: some ActivityFeed, geometry: NotchGeometry) -> Int {
        min(geometry.bubbleCapacity, activities.others.count)
    }
}

/// How an activity is named: in its bubble's accessibility label and in its row of the list.
nonisolated enum ActivityLabel {
    /// The activity's own summary, else its module's name, else the module's id (a module that is not registered, such
    /// as the debug publisher, has no name).
    static func text(summary: String?, displayName: String?, module: ModuleID) -> String {
        summary ?? displayName ?? module.rawValue
    }

    /// For the "+N" bubble and row.
    static func overflow(count: Int) -> String { "Còn \(count) hoạt động khác" }
}
