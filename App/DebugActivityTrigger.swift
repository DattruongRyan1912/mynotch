#if DEBUG
import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// DEBUG builds only: lets the controller exercise several live activities without real apps, by posting the distributed
/// notification `io.lucasvu.mynotch.debug.activities` whose object is a command (see `DebugActivityCommand`). The
/// activities come from this publisher, which belongs to the app and not to a module, under the module id "debug"; one
/// command per second is taken, the rest are dropped. Every change of the primary activity or of the bubbles is logged
/// (category `activities`, notice level) as ids and counts, never content.
final class DebugActivityTrigger {
    static let notificationName = Notification.Name("io.lucasvu.mynotch.debug.activities")
    static let module: ModuleID = "debug"

    /// Registers a handler for what the notification's object carries (nil when it is no string) and returns how to remove it.
    /// A seam: tests deliver objects themselves instead of posting distributed notifications.
    typealias Observe = (_ handler: @escaping @MainActor (String?) -> Void) -> (() -> Void)

    /// The real thing: the distributed notification center, which also hears other processes (the shell).
    static let systemObserve: Observe = { handler in
        let token = DistributedNotificationCenter.default().addObserver(forName: notificationName, object: nil, queue: .main) { notification in
            let object = notification.object as? String
            MainActor.assumeIsolated { handler(object) }
        }
        return { DistributedNotificationCenter.default().removeObserver(token) }
    }

    private static let logger = Log.logger(category: "activities")

    private let center: ActivityCenter
    private let observe: Observe
    private let now: () -> ContinuousClock.Instant
    private let log: (String) -> Void
    private var limiter = DebugCommandLimiter()
    private var removeObserver: (() -> Void)?
    private var changeLog: Task<Void, Never>?

    var isObserving: Bool { removeObserver != nil }

    init(
        activities: ActivityCenter, observe: @escaping Observe = DebugActivityTrigger.systemObserve,
        now: @escaping () -> ContinuousClock.Instant = { .now },
        log: @escaping (String) -> Void = { DebugActivityTrigger.logger.notice("\($0, privacy: .public)") }
    ) {
        center = activities
        self.observe = observe
        self.now = now
        self.log = log
    }

    func start() {
        guard removeObserver == nil else { return }
        removeObserver = observe { [weak self] object in self?.receive(object) }
        changeLog = Task { [center, log] in
            var last: String?
            for await line in Observations({ Self.describe(center) }) where line != last {
                last = line
                log(line)
            }
        }
    }

    /// What the observer calls: whether the command was carried out. Not carried out: an object that is no command
    /// (never logged, it can be anything) or a command less than a second after the one before (which does not count).
    @discardableResult
    func receive(_ object: String?) -> Bool {
        guard let command = DebugActivityCommand(object) else {
            log("command ignored: not a command")
            return false
        }
        guard limiter.accept(at: now()) else {
            log("command ignored: one per second")
            return false
        }
        switch command {
        case .add(let count):
            log("command add \(count)")
            for spec in DebugActivitySpec.added(count: count) { publish(spec) }
            for id in DebugActivitySpec.addIDs.dropFirst(count) { center.clear(id: id, from: Self.module) }
        case .high:
            log("command high")
            publish(.high)
        case .clear:
            log("command clear")
            center.clearAll(from: Self.module)
        }
        return true
    }

    private func publish(_ spec: DebugActivitySpec) {
        let tint = Self.tint(for: spec.priority)
        center.set(LiveActivity(
            id: spec.id, priority: spec.priority, expiresAfter: spec.lifetime,
            leading: AnyView(Image(systemName: spec.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)),
            trailing: AnyView(Text(spec.trailingText).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(tint)),
            summary: spec.summary
        ), from: Self.module)
    }

    /// Dim for low, white for normal, orange for high: the priority can be read off the notch.
    private static func tint(for priority: ActivityPriority) -> Color {
        switch priority {
        case .low: .gray
        case .normal: .white
        case .high, .critical: .orange
        }
    }

    /// Ids and counts of what the notch is showing: the primary, the bubbles and how many are live in all.
    static func describe(_ center: ActivityCenter) -> String {
        let others = center.others.map(\.id).joined(separator: ",")
        return "primary=\(center.current?.id ?? "-") others=[\(others)] total=\(center.ordered.count)"
    }
}
#endif
