import CoreGraphics
import MyNotchCore

/// How long what was understood stays up, and what keeps it or ends it. One at a time: a new one replaces the old.
///
/// It goes after 5 s, unless the pointer is over it, which holds it until the pointer leaves and then 2 s more; at once
/// on `dismiss`, which the watcher calls for a click elsewhere, a key or a changed selection; and when another app than the
/// selection's comes to the front.
///
/// The small translate button is the same with its own times: it comes up 0.3 s after it is decided on, so a quick drag and
/// copy never shows it, and it stays 4 s from then. For a selection made with the mouse it also goes when the pointer moves far
/// from it, and is never shown if the pointer already has; the pointer is asked every quarter second, not listened to, so
/// nothing runs while it travels.
final class SelectionChip {
    static let lifetime = Duration.seconds(5)
    static let lingerAfterHover = Duration.seconds(2)
    static let buttonDelay = Duration.milliseconds(300)
    static let buttonLifetime = Duration.seconds(4)
    static let pointerPoll = Duration.milliseconds(250)
    /// How far (in points) from the selection the pointer may go before the button is taken away.
    static let farAway: CGFloat = 150

    /// What is showing now, or about to: the button is decided on at once and shown after its delay, and ends like anything else
    /// that is showing.

    private(set) var hint: SelectionHint?

    private let scheduler: any Scheduler
    private let showHint: @MainActor (SelectionHint, CGRect) -> Void
    private let hideHint: @MainActor () -> Void
    private let onDismiss: @MainActor () -> Void
    private let pointer: (@MainActor () -> CGPoint)?
    private var isHovering = false
    /// The hint is on screen, not only decided on.
    private var isPresented = false
    private var clock: ScheduledAction?
    private var appearance: ScheduledAction?
    private var pointerWatch: ScheduledAction?

    /// - Parameters:
    ///   - show: puts the hint up, or moves it when one is already up.
    ///   - hide: takes it down.
    ///   - onDismiss: it went, whatever the reason; not called when a hint is replaced.
    ///   - pointer: where the pointer is, for the button's "far away"; nil never takes the button away for that.
    init(
        scheduler: any Scheduler, show: @escaping @MainActor (SelectionHint, CGRect) -> Void, hide: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void, pointer: (@MainActor () -> CGPoint)? = nil
    ) {
        self.scheduler = scheduler
        showHint = show
        hideHint = hide
        self.onDismiss = onDismiss
        self.pointer = pointer
    }

    /// - Parameter watchesPointer: the pointer made the selection, so a button is not shown when the pointer is already far from
    ///   it, and goes when the pointer leaves for far away. (A selection made with the keyboard has no pointer to go by.) Only
    ///   the button looks at it.
    func show(_ hint: SelectionHint, anchor: CGRect, watchesPointer: Bool = false) {
        appearance?.cancel()
        appearance = nil
        stopPointerWatch()
        stopClock()
        if hint.kind == .translateButton, watchesPointer, let pointer, SelectionGeometry.distance(from: pointer(), to: anchor) > Self.farAway {
            // The user has already gone elsewhere: nothing is shown, and what was up is about a selection that is gone.
            return dismiss()
        }
        self.hint = hint
        guard hint.kind == .translateButton else { return present(hint, at: anchor) }
        // What was up is about a selection that is gone: not left on screen for the button's delay.
        if isPresented {
            isPresented = false
            isHovering = false
            hideHint()
        }
        if watchesPointer { watchPointer(near: anchor) }
        appearance = scheduler.schedule(after: Self.buttonDelay) { [weak self] in
            self?.appearance = nil
            self?.present(hint, at: anchor)
        }
    }

    private func present(_ hint: SelectionHint, at anchor: CGRect) {
        isPresented = true
        showHint(hint, anchor)
        if isHovering { stopClock() } else { startClock(hint.kind == .translateButton ? Self.buttonLifetime : Self.lifetime) }
    }

    /// The pointer went over the chip or left it.
    func hoverChanged(_ hovering: Bool) {
        guard isPresented else { return }
        isHovering = hovering
        if hovering { stopClock() } else { startClock(Self.lingerAfterHover) }
    }

    func applicationActivated(_ processID: pid_t) {
        guard let hint, hint.source.application.processID != processID else { return }
        dismiss()
    }

    func dismiss() {
        guard hint != nil else { return }
        stopClock()
        appearance?.cancel()
        appearance = nil
        stopPointerWatch()
        hint = nil
        isHovering = false
        let wasPresented = isPresented
        isPresented = false
        if wasPresented { hideHint() }
        onDismiss()
    }

    /// Asks where the pointer is every quarter second while the button is up, and takes the button away once it is far from the
    /// selection.
    private func watchPointer(near anchor: CGRect) {
        guard let pointer else { return }
        pointerWatch = scheduler.schedule(after: Self.pointerPoll) { [weak self] in
            guard let self, hint != nil else { return }
            if SelectionGeometry.distance(from: pointer(), to: anchor) > Self.farAway { dismiss() } else { watchPointer(near: anchor) }
        }
    }

    private func stopPointerWatch() {
        pointerWatch?.cancel()
        pointerWatch = nil
    }

    private func startClock(_ delay: Duration) {
        clock?.cancel()
        clock = scheduler.schedule(after: delay) { [weak self] in self?.dismiss() }
    }

    private func stopClock() {
        clock?.cancel()
        clock = nil
    }
}
