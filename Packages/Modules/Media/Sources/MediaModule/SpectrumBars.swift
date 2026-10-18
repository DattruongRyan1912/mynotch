import AppKit
import NotchUI
import SwiftUI

/// The bars of `NowPlayingBars`, drawn as one `CALayer` each and moved straight from the store. Nothing here is SwiftUI state, so
/// new levels, about 30 times a second, change layers and never make the notch's hosting view evaluate or lay out its views. The
/// made-up motion, which is what the bars do unless the real spectrum is on, is an animation of the layers: the render server plays
/// it, and nothing is scheduled or drawn from here per frame.
struct SpectrumBars: NSViewRepresentable {
    let store: NowPlayingStore

    func makeNSView(context: Context) -> SpectrumBarsView {
        let view = SpectrumBarsView(store: store, accent: Self.accent(in: context.environment), surface: context.environment.notchSurface)
        view.isNotchOnScreen = context.environment.notchIsOnScreen
        return view
    }

    func updateNSView(_ view: SpectrumBarsView, context: Context) {
        // Handed over on every update, which is as often as the environment changes: the view paints only a colour that is new.
        view.accent = Self.accent(in: context.environment)
        view.surface = context.environment.notchSurface
        view.isNotchOnScreen = context.environment.notchIsOnScreen
    }

    /// The accent of the notch the bars are in, as a layer takes it: the layers do not read the environment themselves.
    private static func accent(in environment: EnvironmentValues) -> CGColor {
        environment.notchAccent.resolve(in: environment).cgColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: SpectrumBarsView, context: Context) -> CGSize? {
        NowPlayingBars.size
    }
}

/// Counts as one bars view on screen for the store (which runs the tap only while there is one) while it is in a window of a
/// notch that can be seen, and while it does, follows the store through its hub: what the store says is shown to every such view
/// at once, so the levels of the tap's bands are worked out once and not once per display.
final class SpectrumBarsView: NSView {
    /// The key of the made-up motion's animation on each bar.
    static let madeUpKey = "madeUp"

    private let store: NowPlayingStore
    private let bars: [CALayer]
    private var levels = [Double](repeating: 0, count: NowPlayingBars.barCount)
    private var isFollowing = false
    private var stopListeningToColors: (() -> Void)?
    /// How many times the layers were painted, for tests: the tap's levels move them and never paint them.
    private(set) var paintCount = 0
    /// The bars are playing the made-up motion, as an animation of each layer that the render server runs: while it does, nothing
    /// is drawn from here, however long it lasts.
    private(set) var isMadeUp = false

    /// The colour of the bars where neither the cover nor the user's choice has one. It is the notch's accent, and the layers
    /// keep what they are given, so a new one is painted at once (the bars that carry other colours are not touched).
    var accent: CGColor {
        didSet {
            guard accent != oldValue, store.spectrumColors == nil else { return }
            paint(nil)
        }
    }

    /// What the notch the view is in is drawn on, from the SwiftUI environment: the collapsed notch's bars and the open tab's are
    /// told alike. The bars' colours are lifted to show on it and glass gives them an edge, so a new surface is painted at once; a
    /// tint of the glass is no new surface for the bars.
    var surface: NotchSurface {
        didSet {
            guard SpectrumBackdrop(surface) != SpectrumBackdrop(oldValue) else { return }
            paint(store.spectrumColors)
        }
    }

    /// Whether the notch the view is in can be seen, from the SwiftUI environment.
    var isNotchOnScreen = true {
        didSet { follow(window != nil && isNotchOnScreen) }
    }

    init(store: NowPlayingStore, accent: CGColor, surface: NotchSurface = .solid) {
        self.store = store
        self.accent = accent
        self.surface = surface
        bars = (0..<NowPlayingBars.barCount).map { _ in
            let bar = CALayer()
            bar.cornerRadius = NowPlayingBars.barWidth / 2
            bar.cornerCurve = .continuous
            // The edge on glass: only its strength changes (`paint`), and it is not a shadow with an offset or a path, which would
            // not follow the height the bar animates through.
            bar.shadowColor = CGColor(gray: 0, alpha: 1)
            bar.shadowOffset = .zero
            bar.shadowRadius = Self.edgeRadius
            return bar
        }
        super.init(frame: CGRect(origin: .zero, size: NowPlayingBars.size))
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
        paint(store.spectrumColors)
        place(levels, animated: false)
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
            // The colours may have changed while the bars were off screen, where nothing followed the store.
            paint(store.spectrumColors)
            stopListeningToColors = store.observeSpectrumColors { [weak self] colors in self?.paint(colors) }
            store.barsHub.attach(self)
        } else {
            store.barsHub.detach(self)
            endMadeUp()
            stopListeningToColors?()
            stopListeningToColors = nil
            store.spectrumViewDisappeared()
        }
    }

    /// How strong the edge of a bar is on glass, and how far it reaches: a 1 pt shadow of black at 35 %, which is what lets a bar read
    /// over a light or a busy backdrop. A layer shadow follows the bar's own shape, as tall as it is at each moment.
    static let edgeOpacity: Float = 0.35
    static let edgeRadius: CGFloat = 1

    /// The colour of each bar, or the accent colour where the store has none, and the edge glass gives them. Set on the layers once
    /// per change, with no animation: a track changes the colours at most once, an accent or a surface change likewise, and nothing
    /// here is SwiftUI state. The store's colours are the choice itself: they are lifted here, for this view's surface (white and any
    /// colour that is light enough already are left as they are). The accent is the user's own pick and is drawn as it is.
    private func paint(_ colors: [SRGBColor]?) {
        paintCount += 1
        let backdrop = SpectrumBackdrop(surface)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            if let colors, colors.indices.contains(index) {
                let color = colors[index].visible(on: backdrop)
                bar.backgroundColor = CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
            } else {
                bar.backgroundColor = accent
            }
            bar.shadowOpacity = backdrop.hasEdge ? Self.edgeOpacity : 0
        }
        CATransaction.commit()
    }

    /// What the hub has the bars show: levels, placed on the layers, or the made-up motion, started at `date`'s place in its loop.
    func show(_ frame: BarsFrame, at date: Date) {
        switch frame {
        case .levels(let newLevels, let animated):
            endMadeUp()
            levels = newLevels
            place(newLevels, animated: animated)
        case .madeUp:
            beginMadeUp(at: date)
        }
    }

    /// The made-up motion of bar `bar`: its height over the loop as a keyframe animation, 30 steps a second as before, held rather than
    /// blended (no in-between heights, no display-rate redraws), and begun at `phase`, the wall clock's place in the loop, so the bars
    /// of every display show the same height. Nothing here is drawn per frame: the render server plays it.
    static func madeUpAnimation(bar: Int, phase: TimeInterval) -> CAKeyframeAnimation {
        let loop = CAKeyframeAnimation(keyPath: "bounds.size.height")
        loop.values = NowPlayingBars.madeUpKeyframes[bar]
        loop.calculationMode = .discrete
        loop.duration = NowPlayingBars.madeUpLoop
        loop.repeatCount = .infinity
        loop.timeOffset = phase
        // The steps come 30 a second: the display need not run the animation at its own rate.
        loop.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        return loop
    }

    /// Starts the made-up motion at `date`'s place in its loop. The layers carry the height the loop begins at, which is what they
    /// show if the animation is taken away.
    private func beginMadeUp(at date: Date) {
        let phase = NowPlayingBars.madeUpPhase(at: date)
        levels = (0..<bars.count).map { NowPlayingBars.level(bar: $0, at: Date(timeIntervalSinceReferenceDate: phase)) }
        place(levels, animated: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.add(Self.madeUpAnimation(bar: index, phase: phase), forKey: Self.madeUpKey)
        }
        CATransaction.commit()
        isMadeUp = true
    }

    /// Takes the made-up motion away, leaving each bar at the height it shows, so a move that eases from here starts from it.
    private func endMadeUp() {
        guard isMadeUp else { return }
        isMadeUp = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            if let shown = bar.presentation() { bar.bounds = shown.bounds }
            bar.removeAnimation(forKey: Self.madeUpKey)
        }
        CATransaction.commit()
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
            let height = NowPlayingBars.height(forLevel: levels[index])
            bar.frame = CGRect(
                x: left + CGFloat(index) * (NowPlayingBars.barWidth + NowPlayingBars.spacing),
                y: (bounds.height - height) / 2, width: NowPlayingBars.barWidth, height: height
            )
        }
        CATransaction.commit()
    }
}
