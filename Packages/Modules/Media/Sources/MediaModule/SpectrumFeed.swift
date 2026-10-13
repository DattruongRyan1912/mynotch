import MyNotchCore
import os

/// Runs the spectrum source only while the bars need it (real spectrum on, music playing, bars on screen)
/// and hands its levels to the store. Lives for one start/stop cycle of the module.
final class SpectrumFeed {
    /// How long the tap outlives the need for it: short gaps (a track change, the notch opening from the
    /// activity to the tab) would otherwise tear it down and rebuild it.
    static let stopDelay: Duration = .seconds(2)

    private let source: any SpectrumSource
    private let store: NowPlayingStore
    private let scheduler: any Scheduler
    private let logger: Logger
    private var isRunning = false
    /// Set when the source could not start; it stays off until the setting is turned off and on again.
    private var hasFailed = false
    private var stopTimer: ScheduledAction?

    init(source: any SpectrumSource, store: NowPlayingStore, scheduler: any Scheduler, logger: Logger) {
        self.source = source
        self.store = store
        self.scheduler = scheduler
        self.logger = logger
    }

    /// Call whenever one of the inputs may have changed; repeated calls with the same inputs do nothing.
    func update(isEnabled: Bool, isPlaying: Bool, isShown: Bool) {
        guard isEnabled else {
            // Off means stop capturing now. A failed tap gets another chance when the setting comes back on.
            hasFailed = false
            store.setSpectrumPermissionLikelyDenied(false)
            stop()
            return
        }
        if isPlaying && isShown && !hasFailed {
            cancelStopTimer()
            guard !isRunning else { return }
            isRunning = true
            // A new tap session judges the permission afresh and never reports "not denied" itself.
            store.setSpectrumPermissionLikelyDenied(false)
            source.start { [weak self] event in self?.receive(event) }
        } else if isRunning && stopTimer == nil {
            stopTimer = scheduler.schedule(after: Self.stopDelay) { [weak self] in self?.stop() }
        }
    }

    /// The module stops: no tap, no permission hint.
    func shutDown() {
        stop()
        store.setSpectrumPermissionLikelyDenied(false)
    }

    private func stop() {
        cancelStopTimer()
        guard isRunning else { return }
        isRunning = false
        source.stop()
        store.showSpectrum(nil)
    }

    private func cancelStopTimer() {
        stopTimer?.cancel()
        stopTimer = nil
    }

    private func receive(_ event: SpectrumEvent) {
        guard isRunning else { return }
        switch event {
        case .bands(let bands):
            // A denied tap keeps delivering silence: the bars keep the made-up motion until sound arrives.
            if !store.spectrumPermissionLikelyDenied { store.showSpectrum(bands) }
        case .permissionLikelyDenied(let likelyDenied):
            store.setSpectrumPermissionLikelyDenied(likelyDenied)
            if likelyDenied { store.showSpectrum(nil) }
        case .failed(let reason):
            logger.error("Real spectrum stopped: \(reason, privacy: .public)")
            hasFailed = true
            stop()
        }
    }
}
