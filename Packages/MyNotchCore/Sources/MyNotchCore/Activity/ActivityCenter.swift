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

    /// Highest priority entry; ties go to the most recently added or raised.
    public private(set) var current: Entry?
    public private(set) var entries: [Entry] = []

    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private var expiries: [String: ScheduledAction] = [:]
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var revision = 0

    public init(scheduler: any Scheduler) {
        self.scheduler = scheduler
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
            expiries[key] = scheduler.schedule(after: lifetime) { [weak self] in
                guard let self, self.entries.contains(where: { $0.id == key && $0.revision == expectedRevision }) else { return }
                self.clear(id: activity.id, from: module)
            }
        }
        recompute()
    }

    /// Moves an existing entry above the others at its priority; `set` alone keeps its place.
    public func raise(id: String, from module: ModuleID) {
        let key = Self.key(id, module)
        guard let index = entries.firstIndex(where: { $0.id == key }) else { return }
        sequence += 1
        let entry = entries[index]
        entries[index] = Entry(module: entry.module, activity: entry.activity, sequence: sequence, revision: entry.revision)
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

    /// Assigns only when the winner changes, so removing a non-current entry doesn't redraw the view.
    private func recompute() {
        let winner = entries.max { ($0.activity.priority, $0.sequence) < ($1.activity.priority, $1.sequence) }
        if winner != current { current = winner }
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
