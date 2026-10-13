import Foundation
import MyNotchCore

/// Polls the pasteboard's change count and hands each new copy to `onCapture`.
/// Content is read only for a new change that is neither paused nor from an excluded app.
final class ClipboardMonitor {
    typealias SourceApp = (bundleID: String?, name: String?)
    typealias CapturePolicy = (paused: Bool, excluded: Set<String>, classifier: ClipboardClassifier)

    private let pasteboard: any PasteboardAccess
    private let scheduler: any Scheduler
    private let interval: Duration
    private let frontmostApp: () -> SourceApp
    private let shouldCapture: () -> CapturePolicy
    private let onCapture: (ClipboardContent, Data?, SourceApp) -> Void
    private var lastChangeCount = 0
    private var nextTick: ScheduledAction?

    /// `shouldCapture` is asked on every change, so setting changes apply without restarting.
    init(
        pasteboard: any PasteboardAccess, scheduler: any Scheduler, interval: Duration = .milliseconds(300),
        frontmostApp: @escaping () -> SourceApp,
        shouldCapture: @escaping () -> CapturePolicy,
        onCapture: @escaping (ClipboardContent, Data?, SourceApp) -> Void
    ) {
        self.pasteboard = pasteboard
        self.scheduler = scheduler
        self.interval = interval
        self.frontmostApp = frontmostApp
        self.shouldCapture = shouldCapture
        self.onCapture = onCapture
    }

    /// Whatever is already on the pasteboard is not captured: it was copied before the monitor ran.
    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount
        scheduleTick()
    }

    func stop() {
        nextTick?.cancel()
        nextTick = nil
    }

    /// Schedules the next tick first, so a `stop()` from `onCapture` cancels it.
    private func tick() {
        scheduleTick()
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        let policy = shouldCapture()
        guard !policy.paused else { return }
        let source = frontmostApp()
        if let bundleID = source.bundleID, policy.excluded.contains(bundleID) { return }
        // Classifying on the main actor is fine for now: TIFF is read only without PNG,
        // and converting even a 96 MB TIFF to PNG measured 0.17 s.
        guard let snapshot = pasteboard.snapshot(),
              case .content(let content, let imageData) = policy.classifier.classify(snapshot) else { return }
        onCapture(content, imageData, source)
    }

    private func scheduleTick() {
        nextTick = scheduler.schedule(after: interval) { [weak self] in self?.tick() }
    }
}
