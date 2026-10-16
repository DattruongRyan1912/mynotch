import Foundation
import MyNotchCore
import NotchUI
import os

/// What moves the bars of a store, whatever the number of displays: one `BarsDriver`, followed by every bars view that is on screen.
/// The tap's bands are worked into levels once and each view only places its layers from them, so a second display costs a few layer
/// updates and not a second driver with its own timers. While no view is on screen, which is while the notch is hidden, the screen
/// locked or asleep, nothing is playing or the activity is not shown, nothing here follows the store.
final class SpectrumBarsHub {
    private struct Entry {
        weak var view: SpectrumBarsView?
    }

    private static let logger = Log.logger(category: "media")

    private unowned let store: NowPlayingStore
    private let now: () -> Date
    private var driver: BarsDriver!
    private var entries: [Entry] = []
    private var stopListening: (() -> Void)?
    private var playingTask: Task<Void, Never>?

    init(store: NowPlayingStore, scheduler: any Scheduler, now: @escaping () -> Date) {
        self.store = store
        self.now = now
        driver = BarsDriver(scheduler: scheduler, now: now) { [weak self] frame in self?.draw(frame) }
    }

    /// How many views follow the store through this hub.
    var viewCount: Int { entries.count(where: { $0.view != nil }) }

    /// A view that can be seen starts following; the first one starts the driver, and a later one is shown what the others show.
    func attach(_ view: SpectrumBarsView) {
        entries.removeAll { $0.view == nil }
        guard !entries.contains(where: { $0.view === view }) else { return }
        entries.append(Entry(view: view))
        Self.logger.debug("Spectrum bars on screen: \(self.entries.count)")
        guard entries.count == 1 else {
            view.show(driver.current, at: now())
            return
        }
        start()
    }

    /// A view that cannot be seen any more; the last one stops the driver.
    func detach(_ view: SpectrumBarsView) {
        entries.removeAll { $0.view == nil || $0.view === view }
        Self.logger.debug("Spectrum bars on screen: \(self.entries.count)")
        if entries.isEmpty { stop() }
    }

    private func start() {
        stopListening = store.observeSpectrum { [weak self] bands in self?.driver.setSpectrum(bands) }
        let store = store
        playingTask = Task { [weak self] in
            // The first value is the current one.
            for await playing in Observations({ store.activityIsPlaying }) { self?.driver.setPlaying(playing) }
        }
        driver.setSpectrum(store.spectrumBands)
        driver.setPlaying(store.activityIsPlaying)
        driver.setOnScreen(true)
    }

    private func stop() {
        driver.setOnScreen(false)
        stopListening?()
        stopListening = nil
        playingTask?.cancel()
        playingTask = nil
    }

    private func draw(_ frame: BarsFrame) {
        if case .levels = frame { NotchPerf.count(.spectrumUpdates) }
        let date = now()
        for entry in entries { entry.view?.show(frame, at: date) }
    }
}
