import AppKit
import CoreText
import NotchUI
import SwiftUI

/// How a karaoke line looks: the font, the colour of what is sung and of what is not.
struct KaraokeStyle: Equatable {
    /// How far the lit part fades out at its edge, so the fill sweeps in softly instead of cutting the letters.
    static let feather: CGFloat = 6

    var fontSize: CGFloat
    var weight: NSFont.Weight
    var lit: NSColor
    var dim: NSColor

    var font: NSFont { NSFont.systemFont(ofSize: fontSize, weight: weight) }

    /// One line of text at this size.
    var lineHeight: CGFloat {
        let font = font
        return ceil(font.ascender - font.descender + font.leading)
    }
}

/// A line of lyrics whose sung part fills word by word: the dim text with the same text lit on top of it, and the lit one
/// masked up to where the line is sung. Placed in the SwiftUI views of the notch or the panel.
///
/// Everything that moves is in the view's layers: it reads the clock when it is given the line, a seek, a pause or a change of
/// rate, and from there the fill is one animation that the render server runs. SwiftUI is never asked to redraw or lay out for
/// it, however long the line.
struct KaraokeLine: View {
    let line: LyricLine
    let store: NowPlayingStore
    let style: KaraokeStyle
    @Environment(\.notchIsOnScreen) private var isOnScreen

    var body: some View {
        // The state is read here, so that what moves the fill (a seek, a pause, another rate) builds a new sweep.
        Sweep(line: line, clock: KaraokeClock(store.state), style: style, isOnScreen: isOnScreen)
    }

    private struct Sweep: NSViewRepresentable {
        let line: LyricLine
        let clock: KaraokeClock
        let style: KaraokeStyle
        let isOnScreen: Bool

        func makeNSView(context: Context) -> KaraokeLineView {
            let view = KaraokeLineView()
            view.show(line: line, clock: clock, style: style, isOnScreen: isOnScreen)
            return view
        }

        func updateNSView(_ view: KaraokeLineView, context: Context) {
            view.show(line: line, clock: clock, style: style, isOnScreen: isOnScreen)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView view: KaraokeLineView, context: Context) -> CGSize? {
            // Nothing here has a width of its own: an unbounded proposal gets a modest one, never an infinite one.
            CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 200, height: proposal.height ?? style.lineHeight)
        }
    }
}

final class KaraokeLineView: NSView {
    static let animationKey = "sweep"

    let dimLayer = CATextLayer()
    let litLayer = CATextLayer()
    /// Shows the part of the lit text that is sung: opaque up to the fill's edge, which fades out over `feather` points.
    let fillMask = CAGradientLayer()

    /// Where each word starts in the text as drawn, in points from its left edge, and last the text's width.
    private(set) var edges: [Double] = []
    var textWidth: CGFloat { CGFloat(edges.last ?? 0) }
    /// What the current animation was made from, nil for a line without word timing.
    private(set) var sweep: KaraokeSweep?
    /// The sweep has been handed to Core Animation and nothing has taken it away since.
    private(set) var isAnimating = false
    /// How many times the text and the sweep have been made, for tests: the same inputs again make nothing.
    private(set) var buildCount = 0

    private let now: () -> Date
    private var line: LyricLine?
    private var clock: KaraokeClock?
    private var style: KaraokeStyle?
    private var onScreen = true
    private var shown: Inputs?

    /// What a build depends on: when it is the same again the running animation is still right.
    private struct Inputs: Equatable {
        var line: LyricLine
        var clock: KaraokeClock
        var style: KaraokeStyle
        var width: CGFloat
        var onScreen: Bool
    }

    /// Whether the notch the line is in can be seen. While it cannot, nothing is animated: the line stands where it was and the
    /// sweep starts again, from the clock, when the notch comes back.
    var isOnScreen: Bool {
        get { onScreen }
        set {
            guard newValue != onScreen else { return }
            onScreen = newValue
            refresh()
        }
    }

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        for text in [dimLayer, litLayer] {
            text.alignmentMode = .left
            text.truncationMode = .end
            text.isWrapped = false
            text.contentsScale = 2
            layer?.addSublayer(text)
        }
        fillMask.startPoint = CGPoint(x: 0, y: 0.5)
        fillMask.endPoint = CGPoint(x: 1, y: 0.5)
        fillMask.anchorPoint = CGPoint(x: 0, y: 0.5)
        fillMask.colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Clicks and hovers belong to the SwiftUI view this sits in.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refresh()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for text in [dimLayer, litLayer] { text.contentsScale = scale }
    }

    /// Shows `line` as the playback `clock` has it sung. Handing over what is shown already changes nothing.
    func show(line: LyricLine, clock: KaraokeClock, style: KaraokeStyle, isOnScreen: Bool? = nil) {
        self.line = line
        self.clock = clock
        self.style = style
        if let isOnScreen { onScreen = isOnScreen }
        // One element that reads the line: its layers say nothing to VoiceOver.
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(line.text)
        refresh()
    }

    private func refresh() {
        // A view with no width yet (SwiftUI makes it before it lays it out) has nothing to build.
        guard let line, let clock, let style, bounds.width > 0 else { return }
        let inputs = Inputs(line: line, clock: clock, style: style, width: bounds.width, onScreen: onScreen)
        guard inputs != shown else { return }
        shown = inputs
        buildCount += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let words = placeText(line, style)
        fillMask.removeAnimation(forKey: Self.animationKey)
        isAnimating = false
        if let words {
            fill(words, clock: clock)
        } else {
            sweep = nil
            litLayer.mask = nil
            dimLayer.isHidden = true
        }
        CATransaction.commit()
    }

    /// Sets the text of both layers, centred, at the font size that fits the row as CoreText measures the line at that size, and
    /// works out where each word starts in that same line, so the fill follows the glyphs that are drawn. Returns the line's
    /// words when it has them, they add up to its text and the text runs left to right.
    private func placeText(_ line: LyricLine, _ style: KaraokeStyle) -> [LyricWord]? {
        let available = bounds.width
        let size = CGFloat(KaraokeFit.size(base: Double(style.fontSize), available: Double(available)) { size in
            Self.metrics(of: line.text, size: CGFloat(size), weight: style.weight).width
        })
        let font = NSFont.systemFont(ofSize: size, weight: style.weight)
        let drawn = Self.metrics(of: line.text, size: size, weight: style.weight)

        let height = min(ceil(drawn.ascent + drawn.descent + drawn.leading), bounds.height)
        let boxWidth = min(ceil(drawn.width) + 1, available)
        let frame = CGRect(x: (available - boxWidth) / 2, y: (bounds.height - height) / 2, width: boxWidth, height: height)
        for (text, color) in [(dimLayer, style.dim), (litLayer, style.lit)] {
            text.string = line.text
            text.font = font
            text.fontSize = size
            text.foregroundColor = color.cgColor
            text.frame = frame
        }

        var words: [LyricWord]?
        if let timed = line.words, timed.map({ $0.text.utf16.count }).reduce(0, +) == line.text.utf16.count,
           !KaraokeFit.hasRightToLeftRun(line.text, font: font) {
            words = timed
        }
        var starts: [Double] = []
        var index = 0
        for word in words ?? [] {
            starts.append(Double(CTLineGetOffsetForStringIndex(drawn.line, index, nil)))
            index += word.text.utf16.count
        }
        edges = starts + [Double(drawn.width)]
        // Word starts that run backwards are no fill to follow: the line is shown whole.
        if (1..<edges.count).contains(where: { edges[$0] < edges[$0 - 1] }) { words = nil }

        let feather = KaraokeStyle.feather
        let maskWidth = max(drawn.width + feather, 1)
        fillMask.bounds = CGRect(x: 0, y: 0, width: maskWidth, height: height)
        fillMask.locations = [0, NSNumber(value: Double(drawn.width / maskWidth)), 1]
        return words
    }

    /// The line as CoreText lays it out at `size`, and its measures.
    private nonisolated static func metrics(of text: String, size: CGFloat, weight: NSFont.Weight) -> (line: CTLine, width: CGFloat, ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (line, width, ascent, descent, leading)
    }

    /// Puts the fill where the line is sung and, while the clock runs and the notch can be seen, animates it to the end of the
    /// line. The layer is left at the end, so when the animation is over (or taken away) it stays there.
    private func fill(_ words: [LyricWord], clock: KaraokeClock) {
        litLayer.mask = fillMask
        dimLayer.isHidden = false
        let position = clock.position(at: now()) ?? -.infinity
        let sweep = KaraokeSweep.make(words: words, edges: edges, position: position, rate: onScreen ? clock.rate : 0)
        self.sweep = sweep
        let width = Double(textWidth)
        let feather = Double(KaraokeStyle.feather)
        func maskX(_ x: Double) -> Double { KaraokeSweep.edge(forFill: x, width: width, feather: feather) - width }
        let y = fillMask.bounds.height / 2
        fillMask.position = CGPoint(x: maskX(sweep.finish), y: y)
        guard !sweep.steps.isEmpty else {
            fillMask.position = CGPoint(x: maskX(sweep.start), y: y)
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = ([sweep.start] + sweep.steps.map(\.x)).map { NSNumber(value: maskX($0)) }
        animation.keyTimes = sweep.keyTimes.map { NSNumber(value: $0) }
        animation.duration = sweep.duration
        animation.calculationMode = .linear
        // A fill at 60 frames a second is smooth, and the display need not run at its 120 or 144 for it.
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        fillMask.add(animation, forKey: Self.animationKey)
        isAnimating = true
    }
}
