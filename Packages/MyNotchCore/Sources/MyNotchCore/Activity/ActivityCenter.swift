import Observation

/// Holds every module's live activities and exposes the one to display.
@Observable
public final class ActivityCenter {
    public struct Entry: Identifiable {
        public let module: ModuleID
        public let activity: LiveActivity
        let sequence: Int
        public var id: String { "\(module.rawValue)/\(activity.id)" }
    }

    /// Highest priority entry; ties go to the most recently set.
    public private(set) var current: Entry?
    public private(set) var entries: [Entry] = []

    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private var expiries: [String: ScheduledAction] = [:]
    @ObservationIgnored private var sequence = 0

    public init(scheduler: any Scheduler) {
        self.scheduler = scheduler
    }

    public func set(_ activity: LiveActivity, from module: ModuleID) {
        sequence += 1
        let entry = Entry(module: module, activity: activity, sequence: sequence)
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        expiries.removeValue(forKey: entry.id)?.cancel()
        if let lifetime = activity.expiresAfter {
            let expectedSequence = entry.sequence
            expiries[entry.id] = scheduler.schedule(after: lifetime) { [weak self] in
                guard let self, self.entries.contains(where: { $0.id == entry.id && $0.sequence == expectedSequence }) else { return }
                self.clear(id: activity.id, from: module)
            }
        }
        recompute()
    }

    public func clear(id: String, from module: ModuleID) {
        let key = "\(module.rawValue)/\(id)"
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

    private func recompute() {
        current = entries.max { ($0.activity.priority, $0.sequence) < ($1.activity.priority, $1.sequence) }
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

    public func clear(id: String) {
        guard isActive else { return }
        center.clear(id: id, from: module)
    }

    public func clearAll() {
        guard isActive else { return }
        center.clearAll(from: module)
    }

    /// Called by the registry when the module stops; also removes everything the module published.
    func invalidate() {
        center.clearAll(from: module)
        isActive = false
    }
}
