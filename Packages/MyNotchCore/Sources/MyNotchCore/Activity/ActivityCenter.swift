import Observation

/// Holds every module's live activities and exposes the one to display.
@Observable
public final class ActivityCenter {
    public struct Entry: Identifiable, Equatable {
        public let module: ModuleID
        public let activity: LiveActivity
        let sequence: Int
        /// Changes on every `set` of this key, so a content update of `current` still notifies its observers.
        let revision: Int
        public var id: String { ActivityCenter.key(activity.id, module) }

        /// `LiveActivity` holds views, so equality is identity, position and revision.
        public static func == (lhs: Self, rhs: Self) -> Bool {
            (lhs.id, lhs.sequence, lhs.revision) == (rhs.id, rhs.sequence, rhs.revision)
        }
    }

    /// The primary activity: the highest priority entry. A tie goes to a notice (an activity with an expiry: a volume
    /// change, "copied", a finished agent), the most recently set one first, so it holds the notch for its few seconds
    /// and the former primary steps back in when it is gone. Among activities without an expiry it goes to the one that
    /// became live first, so a newcomer never takes the notch and an update never makes it flip. `raise` beats both.
    public private(set) var current: Entry?
    /// The activities after `current`, in the same order, at most `maxOthers`: what the notch shows as bubbles.
    public private(set) var others: [Entry] = []
    /// Every live activity in display order, `current` first, with no cap: what a list of all of them shows.
    public private(set) var ordered: [Entry] = []
    /// Every live activity in the order it was added.
    public private(set) var entries: [Entry] = []

    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let maxOthers: Int
    @ObservationIgnored private var expiries: [String: ScheduledAction] = [:]
    /// Rises with each new entry; among activities without an expiry the lowest wins ties. `raise` hands out
    /// `raisedSequence`, which only falls and so stays below every entry added before or after it.
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var raisedSequence = 0
    @ObservationIgnored private var revision = 0

    public init(scheduler: any Scheduler, maxOthers: Int = 3) {
        self.scheduler = scheduler
        self.maxOthers = max(maxOthers, 0)
    }

    /// Adds the activity, or replaces an existing one with the same id in place so frequent
    /// updates don't reorder it among same-priority activities. Expiry restarts from this call.
    public func set(_ activity: LiveActivity, from module: ModuleID) {
        let key = Self.key(activity.id, module)
        revision += 1
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index] = Entry(module: module, activity: activity, sequence: entries[index].sequence, revision: revision)
        } else {
            sequence += 1
            entries.append(Entry(module: module, activity: activity, sequence: sequence, revision: revision))
        }
        expiries.removeValue(forKey: key)?.cancel()
        if let lifetime = activity.expiresAfter {
            let expectedRevision = revision
            expiries[key] = scheduler.schedule(after: lifetime) { [weak self, id = activity.id] in
                guard let self, self.entries.contains(where: { $0.id == key && $0.revision == expectedRevision }) else { return }
                self.clear(id: id, from: module)
            }
        }
        recompute()
    }

    /// Moves an existing entry above the others at its priority, notices included; `set` alone keeps its place.
    public func raise(id: String, from module: ModuleID) {
        let key = Self.key(id, module)
        guard let index = entries.firstIndex(where: { $0.id == key }) else { return }
        raisedSequence -= 1
        let entry = entries[index]
        entries[index] = Entry(module: entry.module, activity: entry.activity, sequence: raisedSequence, revision: entry.revision)
        recompute()
    }

    public func clear(id: String, from module: ModuleID) {
        let key = Self.key(id, module)
        guard entries.contains(where: { $0.id == key }) else { return }
        expiries.removeValue(forKey: key)?.cancel()
        entries.removeAll { $0.id == key }
        recompute()
    }

    public func clearAll(from module: ModuleID) {
        guard entries.contains(where: { $0.module == module }) else { return }
        for entry in entries where entry.module == module {
            expiries.removeValue(forKey: entry.id)?.cancel()
        }
        entries.removeAll { $0.module == module }
        recompute()
    }

    private static func key(_ id: String, _ module: ModuleID) -> String { "\(module.rawValue)/\(id)" }

    /// Priority first; then a raised entry (the most recently raised first), then notices (the most recently set
    /// first), then everything else in the order it became live.
    private static func isShownBefore(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.activity.priority != rhs.activity.priority { return lhs.activity.priority > rhs.activity.priority }
        let (lhsRaised, rhsRaised) = (lhs.sequence < 0, rhs.sequence < 0)
        if lhsRaised || rhsRaised { return lhsRaised && (!rhsRaised || lhs.sequence < rhs.sequence) }
        let (lhsNotice, rhsNotice) = (lhs.activity.expiresAfter != nil, rhs.activity.expiresAfter != nil)
        if lhsNotice != rhsNotice { return lhsNotice }
        return lhsNotice ? lhs.revision > rhs.revision : lhs.sequence < rhs.sequence
    }

    /// Assigns each property only when it changes, so removing an entry nobody shows doesn't redraw a view.
    private func recompute() {
        let sorted = entries.sorted(by: Self.isShownBefore)
        let winner = sorted.first
        let bubbles = Array(sorted.dropFirst().prefix(maxOthers))
        if sorted != ordered { ordered = sorted }
        if winner != current { current = winner }
        if bubbles != others { others = bubbles }
    }
}

/// Module-scoped facade over `ActivityCenter`. Inert after `invalidate()`, so a stopped
/// module's in-flight work cannot bring its activities back.
public final class ActivityPublisher {
    private let center: ActivityCenter
    private let module: ModuleID
    private var isActive = true

    init(center: ActivityCenter, module: ModuleID) {
        self.center = center
        self.module = module
    }

    public func set(_ activity: LiveActivity) {
        guard isActive else { return }
        center.set(activity, from: module)
    }

    public func raise(id: String) {
        guard isActive else { return }
        center.raise(id: id, from: module)
    }

    public func clear(id: String) {
        guard isActive else { return }
        center.clear(id: id, from: module)
    }

    public func clearAll() {
        guard isActive else { return }
        center.clearAll(from: module)
    }

    /// Called by `ModuleContext.cancelAll()` when the module stops; also removes everything the module published.
    func invalidate() {
        guard isActive else { return }
        center.clearAll(from: module)
        isActive = false
    }
}
