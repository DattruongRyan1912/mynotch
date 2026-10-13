import AppKit
import CoreGraphics

/// Follows whether the lock screen is on screen, from the notifications macOS posts around it.
final class LockStateObserver {
    nonisolated static let screenIsLocked = Notification.Name("com.apple.screenIsLocked")
    nonisolated static let screenIsUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    nonisolated enum Event {
        case locked, unlocked, displaySlept, displayWoke, sessionBecameActive

        /// A display waking and a session coming back are when a missed lock or unlock notification is noticed.
        var reconcilesWithSession: Bool { self == .displayWoke || self == .sessionBecameActive }
    }

    /// There is no "session in front" flag on purpose: macOS may report the session leaving on a plain lock,
    /// and hiding on it would silently switch the widget off.
    nonisolated struct State: Equatable {
        var isLocked: Bool
        var isDisplayAsleep = false

        /// Locked with the display on: the only time the lock screen can be seen.
        var isLockScreenVisible: Bool { isLocked && !isDisplayAsleep }

        mutating func apply(_ event: Event) {
            switch event {
            case .locked: isLocked = true
            // Unlocking needs the display on, so a sleep whose wake notification was missed is forgotten here.
            case .unlocked: (isLocked, isDisplayAsleep) = (false, false)
            case .displaySlept: isDisplayAsleep = true
            case .displayWoke: isDisplayAsleep = false
            case .sessionBecameActive: break
            }
        }
    }

    private(set) var state: State
    private let distributed: NotificationCenter
    private let workspace: NotificationCenter
    private let isScreenLocked: () -> Bool
    private var onChange: (@MainActor (State) -> Void)?
    private var registrations: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    /// `distributed` carries the lock and unlock notifications, `workspace` the display and session ones.
    /// `isScreenLocked` reads the session's locked state; tests pass a fake, so they never call into the system.
    init(distributed: NotificationCenter, workspace: NotificationCenter, isScreenLocked: @escaping () -> Bool) {
        self.distributed = distributed
        self.workspace = workspace
        self.isScreenLocked = isScreenLocked
        state = State(isLocked: false)
    }

    /// Reads the current state, then reports each change (not each notification) to `onChange`. Starting again replaces the first start.
    func start(_ onChange: @escaping @MainActor (State) -> Void) {
        stop()
        self.onChange = onChange
        state = State(isLocked: isScreenLocked())
        observe(distributed, Self.screenIsLocked, as: .locked)
        observe(distributed, Self.screenIsUnlocked, as: .unlocked)
        observe(workspace, NSWorkspace.screensDidSleepNotification, as: .displaySlept)
        observe(workspace, NSWorkspace.screensDidWakeNotification, as: .displayWoke)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, as: .sessionBecameActive)
    }

    func stop() {
        onChange = nil
        for registration in registrations { registration.center.removeObserver(registration.token) }
        registrations = []
        state = State(isLocked: false)
    }

    /// Delivered on the main queue, so the state is only ever touched from the main actor and in the order posted.
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, as event: Event) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        registrations.append((center, token))
    }

    private func receive(_ event: Event) {
        guard let onChange else { return }
        var new = state
        new.apply(event)
        // The session is the truth: a notification missed while the screen was asleep must not leave the panel up (or down).
        if event.reconcilesWithSession { new.isLocked = isScreenLocked() }
        guard new != state else { return }
        state = new
        onChange(new)
    }

    /// `CGSSessionScreenIsLocked` is only in the session dictionary while the screen is locked.
    nonisolated static func isScreenLocked(in session: [String: Any]?) -> Bool {
        (session?["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    /// The real session; tests never call it.
    static func isSessionScreenLocked() -> Bool {
        isScreenLocked(in: CGSessionCopyCurrentDictionary() as? [String: Any])
    }
}
