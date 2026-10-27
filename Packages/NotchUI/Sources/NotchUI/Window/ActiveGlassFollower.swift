import AppKit
import Observation

/// Draws the Liquid Glass of a MyNotch window that is not the notch's own panel as the notch's is drawn: as an active window's, with
/// its lensing and rim, though the window is never key (see `ActiveGlassAppearance`). Only while the look is Liquid Glass, and not at
/// all where support turned it off or the running macOS has not got the method. AppKit takes the appearance back on the changes
/// `NotchPanel.resets` lists, so it is given back after each, as the notch's panel does.
@MainActor
public final class ActiveGlassFollower {
    private weak var window: NSWindow?
    private let appearance: ActiveGlassAppearance?
    private let notifications: NotificationCenter
    private var observation: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    /// Only holds the window weakly: the follower never keeps a window alive.
    public init(_ window: NSWindow, interface: NotchInterface = .shared, notifications: NotificationCenter = .default) {
        self.window = window
        self.notifications = notifications
        appearance = NotchGlassSupport.drawsActiveGlass(.standard) ? ActiveGlassAppearance.detect() : nil
        guard appearance != nil else { return }
        set(interface.theme?.look == .liquidGlass)
        observation = Task { [weak self] in
            for await isGlass in Observations({ interface.theme?.look == .liquidGlass }) { self?.set(isGlass) }
        }
    }

    /// Stops following and takes the appearance back. Call it when the window goes.
    public func stop() {
        observation?.cancel()
        observation = nil
        set(false)
    }

    isolated deinit {
        observation?.cancel()
        observers.forEach(notifications.removeObserver)
    }

    private func set(_ isOn: Bool) {
        guard let appearance, let window, isOn != !observers.isEmpty else { return }
        observers.forEach(notifications.removeObserver)
        observers = []
        guard isOn else {
            appearance.release(on: window)
            return
        }
        observers = NotchPanel.resets.map { name, isOwn in
            notifications.addObserver(forName: name, object: isOwn ? window : nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.acquireAgain() }
            }
        }
        appearance.acquire(on: window)
    }

    /// Now, and once more when the run loop turns, since AppKit may take it back just after the change that called this.
    private func acquireAgain() {
        guard let appearance, let window else { return }
        appearance.acquire(on: window)
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !self.observers.isEmpty else { return }
            appearance.acquire(on: window)
        }
    }
}
