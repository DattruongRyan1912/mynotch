import AppKit
import MyNotchCore
import NotchUI
import Observation
import SwiftUI

/// The bars of `NowPlayingBars`, drawn as one `CALayer` each and moved straight from the store. Nothing here is SwiftUI state, so
/// new levels, about 30 times a second, change layers and never make the notch's hosting view evaluate or lay out its views.
struct SpectrumBars: NSViewRepresentable {
    let store: NowPlayingStore

    func makeNSView(context: Context) -> SpectrumBarsView {
        let view = SpectrumBarsView(store: store)
        view.isNotchOnScreen = context.environment.notchIsOnScreen
        return view
    }

    func updateNSView(_ view: SpectrumBarsView, context: Context) {
        view.isNotchOnScreen = context.environment.notchIsOnScreen
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: SpectrumBarsView, context: Context) -> CGSize? {
        NowPlayingBars.size
    }
}

/// Counts as one bars view on screen for the store (which runs the tap only while there is one) while it is in a window of a
/// notch that can be seen, and while it does, follows the store: its playing state and the tap's bands.
final class SpectrumBarsView: NSView {
    private let store: NowPlayingStore
    private let bars: [CALayer]
    private var driver: BarsDriver!
    private var levels = [Double](repeating: 0, count: NowPlayingBars.barCount)
    private var isFollowing = false
    private var stopListening: (() -> Void)?
    private var stopListeningToColors: (() -> Void)?
    private var playingTask: Task<Void, Never>?

    /// Whether the notch the view is in can be seen, from the SwiftUI environment.
    var isNotchOnScreen = true {
        didSet { follow(window != nil && isNotchOnScreen) }
    }

    init(store: NowPlayingStore, scheduler: any Scheduler = TaskScheduler(), now: @escaping () -> Date = Date.init) {
        self.store = store
        bars = (0..<NowPlayingBars.barCount).map { _ in
            let bar = CALayer()
            bar.cornerRadius = NowPlayingBars.barWidth / 2
            bar.cornerCurve = .continuous
            return bar
        }
        super.init(frame: CGRect(origin: .zero, size: NowPlayingBars.size))
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
        paint(store.spectrumColors)
        place(levels, animated: false)
        driver = BarsDriver(scheduler: scheduler, now: now) { [weak self] levels, animated in self?.show(levels, animated: animated) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        follow(false)
    }

    /// Clicks and hovers belong to the SwiftUI view this sits in.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var intrinsicContentSize: NSSize { NowPlayingBars.size }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        follow(window != nil && isNotchOnScreen)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        place(levels, animated: false)
    }

    private func follow(_ shouldFollow: Bool) {
        guard shouldFollow != isFollowing else { return }
        isFollowing = shouldFollow
        if shouldFollow {
            store.spectrumViewAppeared()
            stopListening = store.observeSpectrum { [weak self] bands in self?.driver.setSpectrum(bands) }
            let store = store
            playingTask = Task { [weak self] in
                // The first value is the current one.
                for await playing in Observations({ store.activityIsPlaying }) { self?.driver.setPlaying(playing) }
            }
            // The colours may have changed while the bars were off screen, where nothing followed the store.
            paint(store.spectrumColors)
            stopListeningToColors = store.observeSpectrumColors { [weak self] colors in self?.paint(colors) }
            driver.setSpectrum(store.spectrumBands)
            driver.setPlaying(store.activityIsPlaying)
            driver.setOnScreen(true)
        } else {
            driver.setOnScreen(false)
            stopListeningToColors?()
            stopListeningToColors = nil
            stopListening?()
            stopListening = nil
            playingTask?.cancel()
            playingTask = nil
            store.spectrumViewDisappeared()
        }
    }

    /// The colour of each bar, or the accent colour where the store has none. Set on the layers once per change, with no
    /// animation: a track changes the colours at most once, and nothing here is SwiftUI state.
    private func paint(_ colors: [SRGBColor]?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            if let colors, colors.indices.contains(index) {
                bar.backgroundColor = CGColor(srgbRed: colors[index].red, green: colors[index].green, blue: colors[index].blue, alpha: 1)
            } else {
                bar.backgroundColor = NSColor(NotchTokens.accent).cgColor
            }
        }
        CATransaction.commit()
    }

    private func show(_ newLevels: [Double], animated: Bool) {
        NotchPerf.count(.spectrumUpdates)
        levels = newLevels
        place(newLevels, animated: animated)
    }

    /// The bars side by side, each as tall as its level says and centred in the view, with no implicit animation unless asked.
    private func place(_ levels: [Double], animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        let width = NowPlayingBars.size.width
        let left = (bounds.width - width) / 2
        for (index, bar) in bars.enumerated() {
            let height = NowPlayingBars.minHeight + (NowPlayingBars.maxHeight - NowPlayingBars.minHeight) * levels[index]
            bar.frame = CGRect(
                x: left + CGFloat(index) * (NowPlayingBars.barWidth + NowPlayingBars.spacing),
                y: (bounds.height - height) / 2, width: NowPlayingBars.barWidth, height: height
            )
        }
        CATransaction.commit()
    }
}
