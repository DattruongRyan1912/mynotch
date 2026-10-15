import CoreGraphics
import MyNotchCore

/// How long what was understood stays up, and what keeps it or ends it. One at a time: a new one replaces the old.
///
/// It goes after 5 s, unless the pointer is over it, which holds it until the pointer leaves and then 2 s more; at once
/// on `dismiss`, which the watcher calls for a click elsewhere, a key or a changed selection; and when another app than the
/// selection's comes to the front.
final class SelectionChip {
    static let lifetime = Duration.seconds(5)
    static let lingerAfterHover = Duration.seconds(2)

    /// What is showing now.
    private(set) var hint: SelectionHint?

    private let scheduler: any Scheduler
    private let showHint: @MainActor (SelectionHint, CGRect) -> Void
    private let hideHint: @MainActor () -> Void
    private let onDismiss: @MainActor () -> Void
    private var isHovering = false
    private var clock: ScheduledAction?

    /// - Parameters:
    ///   - show: puts the hint up, or moves it when one is already up.
    ///   - hide: takes it down.
    ///   - onDismiss: it went, whatever the reason; not called when a hint is replaced.
    init(
        scheduler: any Scheduler, show: @escaping @MainActor (SelectionHint, CGRect) -> Void, hide: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.scheduler = scheduler
        showHint = show
        hideHint = hide
        self.onDismiss = onDismiss
    }

    func show(_ hint: SelectionHint, anchor: CGRect) {
        self.hint = hint
        showHint(hint, anchor)
        if isHovering { stopClock() } else { startClock(Self.lifetime) }
    }

    /// The pointer went over the chip or left it.
    func hoverChanged(_ hovering: Bool) {
        guard hint != nil else { return }
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
        hint = nil
        isHovering = false
        hideHint()
        onDismiss()
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
