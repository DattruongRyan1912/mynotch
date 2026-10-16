import AppKit
import Darwin
import MyNotchCore
import Observation

/// Hands the memory the app has freed back to the system. A closed library or a settled notch leaves free pages in malloc's small
/// zones, and they stay in the app's footprint until something asks for them: the heap shrinks, the number Activity Monitor shows does
/// not. `malloc_zone_pressure_relief` asks. It runs on a utility queue, never on the main thread, because it takes the zones' locks.
///
/// It runs a while after the notch collapses and after a window goes away (the library, Settings, an editor, a preview), and only
/// once things have been quiet that long: each new reason starts the wait again. It never runs while a notch is open, so a hover that
/// is opening the notch never meets it, and an opening notch cancels one that is waiting.
public final class MemoryRelief {
    /// After the notch collapses. A pointer that slips off and back on opens it again at once, and the relief has nothing to do
    /// with a notch someone is using.
    public static let collapseDelay: Duration = .seconds(5)
    /// After a window goes away. AppKit says a window is closing before the window lets go of its views and models, so the relief
    /// waits for them to be freed.
    public static let windowDelay: Duration = .seconds(2)

    /// Bytes handed back to the system; the debug log says how many.
    typealias Relieve = @Sendable () -> Int

    nonisolated private static let logger = Log.logger(category: "perf")

    private let scheduler: any Scheduler
    private let relieve: Relieve
    private let report: @Sendable (Int) -> Void
    private let perform: (@escaping @Sendable () -> Void) -> Void
    private let notifications: NotificationCenter
    private var pending: ScheduledAction?
    private var isNotchExpanded = false
    private var observers: [NSObjectProtocol] = []
    private var following: Task<Void, Never>?

    public convenience init(scheduler: any Scheduler) {
        self.init(scheduler: scheduler, relieve: Self.systemRelief, report: Self.log(bytes:), perform: Self.onUtilityQueue, notifications: .default)
    }

    /// The pieces a test replaces: what gives memory back, where it goes, where it runs and which center says a window went away.
    init(
        scheduler: any Scheduler,
        relieve: @escaping Relieve,
        report: @escaping @Sendable (Int) -> Void,
        perform: @escaping (@escaping @Sendable () -> Void) -> Void,
        notifications: NotificationCenter
    ) {
        self.scheduler = scheduler
        self.relieve = relieve
        self.report = report
        self.perform = perform
        self.notifications = notifications
    }

    /// Follows the notches (`isNotchExpanded` is read in an observation) and the app's windows. Later calls do nothing.
    public func start(isNotchExpanded: @escaping () -> Bool) {
        guard observers.isEmpty else { return }
        // Closing a window, and ordering one out (the floating panels and previews hide instead of closing).
        observers = [
            notifications.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
                let isNotch = note.object is NotchPanel
                MainActor.assumeIsolated { if !isNotch { self?.windowWentAway() } }
            },
            notifications.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
                // A window that is only covered is still there; the notch's own panels are ordered in and out all day.
                let window = note.object as? NSWindow
                MainActor.assumeIsolated {
                    if let window, !window.isVisible, !(window is NotchPanel) { self?.windowWentAway() }
                }
            },
        ]
        following = Task { [weak self] in
            for await expanded in Observations({ isNotchExpanded() }) { self?.notchChanged(isExpanded: expanded) }
        }
    }

    func stop() {
        observers.forEach(notifications.removeObserver)
        observers = []
        following?.cancel()
        following = nil
        pending?.cancel()
        pending = nil
    }

    /// Whether a relief is waiting for its delay to pass.
    var isPending: Bool { pending != nil }

    func notchChanged(isExpanded expanded: Bool) {
        guard expanded != isNotchExpanded else { return }
        isNotchExpanded = expanded
        if expanded {
            cancel()
        } else {
            wait(for: Self.collapseDelay)
        }
    }

    func windowWentAway() {
        // The notch's own collapse relieves the memory the window left, a moment after it closes.
        guard !isNotchExpanded else { return }
        wait(for: Self.windowDelay)
    }

    private func wait(for delay: Duration) {
        pending?.cancel()
        pending = scheduler.schedule(after: delay) { [weak self] in
            self?.pending = nil
            self?.run()
        }
    }

    private func cancel() {
        pending?.cancel()
        pending = nil
    }

    private func run() {
        guard !isNotchExpanded else { return }
        let (relieve, report) = (relieve, report)
        perform { report(relieve()) }
    }

    /// `malloc_zone_pressure_relief` over every zone, with no goal: all the free pages it can find.
    nonisolated static func systemRelief() -> Int {
        malloc_zone_pressure_relief(nil, 0)
    }

    nonisolated private static func log(bytes: Int) {
        logger.debug("memory relief returned \(bytes) bytes")
    }

    nonisolated static func onUtilityQueue(_ work: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .utility).async(execute: work)
    }
}
