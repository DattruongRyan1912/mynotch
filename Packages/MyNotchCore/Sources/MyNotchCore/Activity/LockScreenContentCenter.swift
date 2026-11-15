import Observation
import SwiftUI

/// Small, non-sensitive views that modules offer for the lock screen. One entry per module; the lock screen
/// module reads this and never depends on the modules that fill it.
@Observable
public final class LockScreenContentCenter {
    public struct Entry: Identifiable {
        public let module: ModuleID
        public let priority: ActivityPriority
        public let view: AnyView
        /// The view has controls to press (the lock screen's panel takes clicks only then). Whether the user lets them show
        /// is the lock screen module's setting, which the view reads from `lockScreenControlsEnabled`.
        public let isInteractive: Bool
        let sequence: Int
        public var id: ModuleID { module }
    }

    /// In registration order; replacing a module's view keeps its place.
    public private(set) var entries: [Entry] = []

    @ObservationIgnored private var sequence = 0

    public init() {}

    /// Highest priority entry; ties go to the most recently added.
    public var current: Entry? { current(allowing: { _ in true }) }

    /// Like `current`, over the contributors `isAllowed` accepts, e.g. the ones the user switched on.
    public func current(allowing isAllowed: (ModuleID) -> Bool) -> Entry? {
        entries.filter { isAllowed($0.module) }.max { ($0.priority, $0.sequence) < ($1.priority, $1.sequence) }
    }

    /// Adds the module's view, or replaces the one it already has in place. `isInteractive` says it has controls to press.
    public func set(_ view: AnyView, priority: ActivityPriority, isInteractive: Bool = false, from module: ModuleID) {
        if let index = entries.firstIndex(where: { $0.module == module }) {
            entries[index] = Entry(
                module: module, priority: priority, view: view, isInteractive: isInteractive, sequence: entries[index].sequence
            )
        } else {
            sequence += 1
            entries.append(Entry(module: module, priority: priority, view: view, isInteractive: isInteractive, sequence: sequence))
        }
    }

    public func clear(from module: ModuleID) {
        guard entries.contains(where: { $0.module == module }) else { return }
        entries.removeAll { $0.module == module }
    }
}

/// Module-scoped facade over `LockScreenContentCenter`. Inert after `invalidate()`, so a stopped
/// module's in-flight work cannot put its view back on the lock screen.
public final class LockScreenPublisher {
    private let center: LockScreenContentCenter
    private let module: ModuleID
    private var isActive = true

    init(center: LockScreenContentCenter, module: ModuleID) {
        self.center = center
        self.module = module
    }

    /// Offers `view` for the lock screen. It must show only what is fine for anyone to read over the user's shoulder. With
    /// `isInteractive` the view has buttons: the panel takes clicks only while such a view is shown and the user allows controls,
    /// and the view draws its buttons only while `lockScreenControlsEnabled` is true.
    public func set(_ view: AnyView, priority: ActivityPriority = .normal, isInteractive: Bool = false) {
        guard isActive else { return }
        center.set(view, priority: priority, isInteractive: isInteractive, from: module)
    }

    public func clear() {
        guard isActive else { return }
        center.clear(from: module)
    }

    /// What the lock screen would show now; read-only, for the module that draws it.
    public func current(allowing isAllowed: (ModuleID) -> Bool) -> LockScreenContentCenter.Entry? {
        center.current(allowing: isAllowed)
    }

    /// Called by `ModuleContext.cancelAll()` when the module stops; also removes the module's view.
    func invalidate() {
        guard isActive else { return }
        center.clear(from: module)
        isActive = false
    }
}

extension EnvironmentValues {
    /// Whether the lock screen lets a view's controls show. The lock screen module sets it from its own setting, so a module
    /// that offers a view with buttons (Media) can draw it read-only without knowing the module. True anywhere else.
    @Entry public var lockScreenControlsEnabled: Bool = true

    /// Whether the lock screen lets a view show lyrics ("Hiện lời bài hát trên màn hình khoá"), a switch apart from the controls.
    /// The lock screen module sets it from its own setting, so Media can leave the lines out without knowing the module. True
    /// anywhere else.
    @Entry public var lockScreenLyricsEnabled: Bool = true
}
