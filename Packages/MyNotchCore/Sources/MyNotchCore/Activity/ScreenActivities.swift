import Observation

/// What a reader sees of the live activities: the one to show, the ones that come after it, all of them in order, and how many are left out.
/// The center has one for every screen (`ActivityCenter.screen(_:)`) and one for no screen in particular, which is the center's own
/// `current`, `others`, `ordered` and `hiddenCount`.
public protocol ActivityFeed: AnyObject {
    var current: ActivityCenter.Entry? { get }
    var others: [ActivityCenter.Entry] { get }
    var ordered: [ActivityCenter.Entry] { get }
    var hiddenCount: Int { get }
}

/// The live activities as one screen's notch has them: the center's order and rules, with the activities that are not shown on that screen
/// (`LiveActivity.displayScope`) left out as if they did not exist. The primary activity of a screen is the highest one that is shown on it,
/// and when there is none the notch there is idle, whatever the other screens show.
///
/// The center keeps it up to date and assigns each property only when it changes, as it does its own, so a notch that reads it is drawn again
/// for nothing that is not on its screen. Made by `ActivityCenter.screen(_:)`.
@Observable
public final class ScreenActivities: ActivityFeed {
    /// The display this is for; nil for every activity, whatever its scope.
    public let display: String?
    public private(set) var current: ActivityCenter.Entry?
    public private(set) var others: [ActivityCenter.Entry] = []
    public private(set) var ordered: [ActivityCenter.Entry] = []
    public private(set) var hiddenCount = 0

    @ObservationIgnored private let maxOthers: Int

    init(display: String?, maxOthers: Int, sorted: [ActivityCenter.Entry]) {
        self.display = display
        self.maxOthers = maxOthers
        update(from: sorted)
    }

    /// Takes the center's entries in display order.
    func update(from sorted: [ActivityCenter.Entry]) {
        let shown = display.map { display in sorted.filter { $0.activity.displayScope.includes(display) } } ?? sorted
        let bubbles = Array(shown.dropFirst().prefix(maxOthers))
        let hidden = max(shown.count - 1 - bubbles.count, 0)
        if shown != ordered { ordered = shown }
        if shown.first != current { current = shown.first }
        if bubbles != others { others = bubbles }
        if hidden != hiddenCount { hiddenCount = hidden }
    }
}
