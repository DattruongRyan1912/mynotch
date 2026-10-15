import AppKit
import CoreText
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

/// The layers of one karaoke line: a dim text, the same text lit and masked, and the mask's one animation. Nothing is shown on a
/// screen: the views are never put in a window that is ordered in.
@Suite struct KaraokeLineViewTests {
    let origin = Date(timeIntervalSince1970: 8_000)
    let style = KaraokeStyle(fontSize: 12, weight: .semibold, lit: .white, dim: NSColor.white.withAlphaComponent(0.5))
    /// Sung from the first second: "one " 1…2 s, "two " 2…3 s, "three" 3…5 s.
    let line = LyricLine(time: 1, words: [
        LyricWord(text: "one ", begin: 1, end: 2), LyricWord(text: "two ", begin: 2, end: 3), LyricWord(text: "three", begin: 3, end: 5),
    ])

    func clock(elapsed: Double, playing: Bool = true, rate: Double = 1) -> KaraokeClock {
        KaraokeClock(NowPlayingState(
            bundleIdentifier: "x", title: "t", durationSeconds: 100,
            elapsedAnchor: PlaybackAnchor(elapsedSeconds: elapsed, timestamp: origin, rate: rate), isPlaying: playing
        ))
    }

    func makeView(width: CGFloat = 300) -> KaraokeLineView {
        let view = KaraokeLineView(now: { origin })
        view.frame = CGRect(x: 0, y: 0, width: width, height: 16)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func animation(_ view: KaraokeLineView) -> CAKeyframeAnimation? {
        view.fillMask.animation(forKey: KaraokeLineView.animationKey) as? CAKeyframeAnimation
    }

    /// Where the mask's layer sits when the fill is at `x`.
    func maskX(_ x: Double, in view: KaraokeLineView) -> Double {
        KaraokeSweep.edge(forFill: x, width: view.textWidth, feather: KaraokeStyle.feather) - view.textWidth
    }

    // MARK: layers

    @Test func theTextIsInTwoLayersTheSungOneMaskedByTheFill() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 0, playing: false), style: style)
        let layers = try #require(view.layer?.sublayers?.compactMap { $0 as? CATextLayer })
        #expect(layers.count == 2)
        #expect(layers.allSatisfy { ($0.string as? String) == "one two three" })
        #expect(view.litLayer.mask === view.fillMask)
        #expect(view.dimLayer.mask == nil)
        #expect(view.litLayer.foregroundColor == NSColor.white.cgColor)
        #expect(view.dimLayer.foregroundColor == NSColor.white.withAlphaComponent(0.5).cgColor)
        #expect(view.litLayer.fontSize == 12 && view.dimLayer.fontSize == 12)
    }

    @Test func aLineThatFitsIsCentredInTheRow() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 0, playing: false), style: style)
        #expect(view.textWidth > 0 && view.textWidth < 300)
        #expect(abs(view.litLayer.frame.midX - 150) < 0.5)
        #expect(view.litLayer.frame == view.dimLayer.frame)
        #expect(abs(view.litLayer.frame.midY - 8) < 0.5)
    }

    @Test func aLineTooWideForItsRowIsScaledDownAndCutAtItsEnd() {
        let long = LyricLine(time: 1, words: (0..<30).map { LyricWord(text: "word\($0) ", begin: 1 + Double($0), end: 2 + Double($0)) })
        let view = makeView(width: 200)
        view.show(line: long, clock: clock(elapsed: 0, playing: false), style: style)
        #expect(abs(view.litLayer.fontSize - 12 * KaraokeFit.minimumScale) < 1e-9)
        // Cut at its end, the fill still never runs backwards and stays inside what is drawn.
        #expect(zip(view.edges, view.edges.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(view.litLayer.frame.width <= 200)
        #expect(view.litLayer.truncationMode == .end)
        // A little too wide is scaled to fit and not cut.
        let slightly = LyricLine(time: 1, words: [LyricWord(text: "a fairly long line of words ", begin: 1, end: 2), LyricWord(text: "to sing", begin: 2, end: 3)])
        let narrow = makeView(width: 150)
        narrow.show(line: slightly, clock: clock(elapsed: 0, playing: false), style: style)
        #expect(narrow.litLayer.fontSize < 12 && narrow.litLayer.fontSize >= 12 * KaraokeFit.minimumScale)
    }

    @Test func aLineWithoutWordsIsShownLitAndWhole() {
        let view = makeView()
        view.show(line: LyricLine(time: 1, text: "plain line"), clock: clock(elapsed: 1.5), style: style)
        #expect(view.litLayer.mask == nil)
        #expect(animation(view) == nil)
        #expect((view.litLayer.string as? String) == "plain line")
        #expect(view.dimLayer.isHidden)
    }

    @Test func theViewLeavesClicksToTheSwiftUIViewItSitsIn() {
        #expect(makeView().hitTest(CGPoint(x: 5, y: 5)) == nil)
    }

    // MARK: the fill

    @Test func aPausedLineIsFilledUpToWhereItIsSungAndNothingMoves() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 2.5, playing: false), style: style)
        #expect(animation(view) == nil)
        let sweep = try #require(view.sweep)
        #expect(sweep.steps.isEmpty)
        // Half of "two ", so past the end of "one " and before the end of "two ".
        let ones = view.edges
        #expect(sweep.start > ones[1] && sweep.start < ones[2])
        #expect(abs(sweep.start - (ones[1] + ones[2]) / 2) < 1e-9)
        #expect(abs(Double(view.fillMask.position.x) - maskX(sweep.start, in: view)) < 1e-6)
    }

    @Test func beforeTheFirstWordNothingIsLitAndAfterTheLastEverythingIs() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 0, playing: false), style: style)
        #expect(abs(Double(view.fillMask.position.x) - maskX(0, in: view)) < 1e-6)
        // The mask's soft edge is wholly before the text.
        #expect(Double(view.fillMask.position.x) + Double(view.fillMask.bounds.width) <= 1e-6)
        view.show(line: line, clock: clock(elapsed: 9, playing: false), style: style)
        #expect(abs(Double(view.fillMask.position.x) - maskX(view.textWidth, in: view)) < 1e-6)
        #expect(Double(view.fillMask.position.x) <= 1e-6)
    }

    @Test func aPlayingLineIsOneAnimationOfTheMaskWhichTheRenderServerRuns() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        let keyframes = try #require(animation(view))
        let sweep = try #require(view.sweep)
        #expect(keyframes.keyPath == "position.x")
        #expect(abs(keyframes.duration - sweep.duration) < 1e-9)
        #expect(keyframes.calculationMode == .linear)
        #expect(keyframes.keyTimes?.map(\.doubleValue) == sweep.keyTimes)
        let values = try #require(keyframes.values as? [Double])
        #expect(values.count == sweep.steps.count + 1)
        #expect(abs(values[0] - maskX(sweep.start, in: view)) < 1e-6)
        #expect(abs(values[values.count - 1] - maskX(sweep.finish, in: view)) < 1e-6)
        // Afterwards the layer stays where the animation ends.
        #expect(abs(Double(view.fillMask.position.x) - maskX(sweep.finish, in: view)) < 1e-6)
        #expect(abs(sweep.finish - Double(view.textWidth)) < 1e-9)
    }

    @Test func aFasterClockMakesTheAnimationShorter() throws {
        let normal = makeView()
        normal.show(line: line, clock: clock(elapsed: 1.5), style: style)
        let fast = makeView()
        fast.show(line: line, clock: clock(elapsed: 1.5, rate: 2), style: style)
        let normalDuration = try #require(animation(normal)).duration
        let fastDuration = try #require(animation(fast)).duration
        #expect(abs(normalDuration / fastDuration - 2) < 1e-9)
    }

    @Test func theSameLineAndClockAgainLeaveTheRunningAnimationAlone() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.layoutSubtreeIfNeeded()
        #expect(view.buildCount == 1)
    }

    @Test func aSeekMakesANewAnimationFromWhereItLands() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        let before = try #require(view.sweep).start
        view.show(line: line, clock: clock(elapsed: 3.5), style: style)
        #expect(view.buildCount == 2)
        #expect(try #require(view.sweep).start > before)
        #expect(animation(view) != nil)
    }

    @Test func pausingTakesTheAnimationAwayAndKeepsTheFill() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.show(line: line, clock: clock(elapsed: 1.5, playing: false), style: style)
        #expect(animation(view) == nil)
        let sweep = try #require(view.sweep)
        #expect(abs(Double(view.fillMask.position.x) - maskX(sweep.start, in: view)) < 1e-6)
    }

    @Test func aLineThatIsAlreadySungHasNoAnimationAndIsAllLit() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 50), style: style)
        #expect(animation(view) == nil)
        #expect(abs(Double(view.fillMask.position.x) - maskX(view.textWidth, in: view)) < 1e-6)
    }

    @Test func aNewLineReplacesTheOldOne() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        let next = LyricLine(time: 6, words: [LyricWord(text: "four ", begin: 6, end: 7), LyricWord(text: "five", begin: 7, end: 8)])
        view.show(line: next, clock: clock(elapsed: 6.5), style: style)
        #expect((view.litLayer.string as? String) == "four five")
        #expect((view.dimLayer.string as? String) == "four five")
        #expect(try #require(view.sweep).steps.last?.x == view.textWidth)
    }

    // MARK: a line shrunk to fit is drawn whole, and the fill follows its glyphs

    static let vietnamese = "Tôi yêu em người ơi, hãy ở lại với tôi đêm nay"

    func vietnameseLine() -> LyricLine {
        let texts = Self.vietnamese.split(separator: " ").map(String.init)
        return LyricLine(time: 1, words: texts.enumerated().map { index, text in
            LyricWord(text: index == texts.count - 1 ? text : text + " ", begin: 1 + Double(index), end: 2 + Double(index))
        })
    }

    /// CoreText's own width of `text` in the style's font at `size`.
    func coreTextWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> Double {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    /// The right edge of the ink of `layer`'s text as it is drawn (in points from the layer's left edge), found by drawing the layer
    /// into a bitmap at two pixels to the point, which is how the notch is drawn on a Retina display.
    func inkRightEdge(of layer: CATextLayer, width: CGFloat) -> Double {
        let scale = 2
        let height = Int(ceil(layer.bounds.height))
        let pixelsWide = Int(ceil(width)) * scale
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: pixelsWide, height: height * scale, bitsPerComponent: 8, bytesPerRow: pixelsWide * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return -1 }
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        layer.contentsScale = CGFloat(scale)
        layer.render(in: context)
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var right = -1
        for x in stride(from: pixelsWide - 1, through: 0, by: -1) {
            for y in 0..<(height * scale) where pixels[(y * pixelsWide + x) * 4 + 3] > 24 {
                right = x
                break
            }
            if right >= 0 { break }
        }
        return right < 0 ? -1 : Double(right + 1) / Double(scale)
    }

    /// A copy of the layer's text with all the room it can want, to see where it would end.
    func naturalLayer(like layer: CATextLayer, width: CGFloat) -> CATextLayer {
        let natural = CATextLayer()
        natural.string = layer.string
        natural.font = layer.font
        natural.fontSize = layer.fontSize
        natural.foregroundColor = CGColor(gray: 1, alpha: 1)
        natural.alignmentMode = .left
        natural.isWrapped = false
        natural.truncationMode = .none
        natural.frame = CGRect(x: 0, y: 0, width: width, height: layer.bounds.height)
        return natural
    }

    nonisolated struct Fit: CustomTestStringConvertible, Sendable {
        var name: String
        var scale: Double
        var testDescription: String { "\(name) at \(scale)" }
    }

    /// The strip's, the tab row's and a 22 pt bold panel's styles, each with a row 0.85 and 0.7 as wide as the line is.
    nonisolated static let fits = [
        Fit(name: "strip", scale: 0.85), Fit(name: "strip", scale: 0.7), Fit(name: "row", scale: 0.85), Fit(name: "row", scale: 0.7),
        Fit(name: "panel", scale: 0.85), Fit(name: "panel", scale: 0.7),
    ]

    func style(of fit: Fit) -> KaraokeStyle {
        switch fit.name {
        case "strip": .strip
        case "row": .row
        default: KaraokeStyle(fontSize: 22, weight: .bold, lit: .white, dim: .gray)
        }
    }

    @Test(arguments: fits)
    func aLineShrunkToFitIsDrawnWholeWithNoEllipsis(fit: Fit) throws {
        let line = vietnameseLine()
        // A row `scale` as wide as the line is at its full size: the shrink the old code measured linearly.
        let natural = coreTextWidth(line.text, size: style(of: fit).fontSize, weight: style(of: fit).weight)
        let width = ceil(natural * fit.scale)
        let view = makeView(width: width)
        view.show(line: line, clock: clock(elapsed: 9_999, playing: false), style: style(of: fit))
        let drawnSize = Double(view.litLayer.fontSize)
        #expect(drawnSize < style(of: fit).fontSize && drawnSize >= style(of: fit).fontSize * KaraokeFit.minimumScale)
        // What CoreText says the line is at the size it is drawn at fits the row, and the text layer's box holds it.
        let measured = coreTextWidth(line.text, size: CGFloat(drawnSize), weight: style(of: fit).weight)
        #expect(measured <= width, "\(measured) of \(width)")
        #expect(abs(Double(view.textWidth) - measured) < 0.01)
        #expect(Double(view.litLayer.frame.width) >= measured)
        #expect(Double(view.litLayer.frame.width) <= width)
        // Drawn: the ink of the line the view has reaches the end of the line (an ellipsis would stop short of it).
        let drawn = inkRightEdge(of: view.dimLayer, width: width)
        let wide = inkRightEdge(of: naturalLayer(like: view.dimLayer, width: width * 2), width: width * 2)
        #expect(abs(drawn - wide) <= 1, "drawn \(drawn) against the whole line's \(wide)")
        #expect(abs(drawn - measured) <= 1, "drawn \(drawn) against CoreText's \(measured)")
        #expect(drawn <= Double(view.litLayer.frame.width) + 0.5)
    }

    @Test(arguments: fits)
    func theFillsEdgesAreWhereTheGlyphsOfTheDrawnLineAre(fit: Fit) throws {
        let line = vietnameseLine()
        let natural = coreTextWidth(line.text, size: style(of: fit).fontSize, weight: style(of: fit).weight)
        let view = makeView(width: ceil(natural * fit.scale))
        view.show(line: line, clock: clock(elapsed: 3.5), style: style(of: fit))
        let font = NSFont.systemFont(ofSize: view.litLayer.fontSize, weight: style(of: fit).weight)
        let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: [.font: font]))
        let words = try #require(line.words)
        #expect(view.edges.count == words.count + 1)
        var index = 0
        for (word, edge) in zip(words, view.edges) {
            let glyphs = Double(CTLineGetOffsetForStringIndex(ctLine, index, nil))
            #expect(abs(edge - glyphs) <= 1, "\(word.text): edge \(edge) against glyphs at \(glyphs)")
            index += word.text.utf16.count
        }
        #expect(abs((view.edges.last ?? 0) - CTLineGetTypographicBounds(ctLine, nil, nil, nil)) <= 1)
        // The last word's end is the end of the drawn text, so the last word lights up fully.
        #expect(abs((view.sweep?.finish ?? -1) - Double(view.textWidth)) <= 1)
    }

    @Test func aLineThatFitsIsMeasuredAndDrawnAtItsFullSizeAndItsEdgesAreItsGlyphs() throws {
        let line = vietnameseLine()
        let view = makeView(width: 400)
        view.show(line: line, clock: clock(elapsed: 3.5, playing: false), style: style)
        #expect(view.litLayer.fontSize == 12)
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: [.font: font]))
        #expect(abs(Double(view.textWidth) - CTLineGetTypographicBounds(ctLine, nil, nil, nil)) < 0.01)
        let drawn = inkRightEdge(of: view.dimLayer, width: 400)
        #expect(abs(drawn - Double(view.textWidth)) <= 1)
    }

    @Test func aLineWiderThanEvenTheSmallestSizeIsCutAtItsEndAndTheFillStaysInside() throws {
        let long = LyricLine(time: 1, words: (0..<30).map { LyricWord(text: "word\($0) ", begin: 1 + Double($0), end: 2 + Double($0)) })
        let view = makeView(width: 200)
        view.show(line: long, clock: clock(elapsed: 5), style: style)
        #expect(abs(view.litLayer.fontSize - 12 * KaraokeFit.minimumScale) < 1e-9)
        #expect(view.litLayer.frame.width <= 200)
        #expect(view.litLayer.truncationMode == .end)
        #expect(zip(view.edges, view.edges.dropFirst()).allSatisfy { $0 <= $1 })
        let mask = Double(view.fillMask.position.x) + Double(view.fillMask.bounds.width)
        #expect(mask.isFinite)
    }

    // MARK: right-to-left lines are shown whole

    @Test(arguments: ["مرحبا بالعالم الجميل", "שלום עולם יפה", "hello مرحبا world", "hello שלום", "שלום hello"])
    func aLineWithRightToLeftTextHasNoSweepAndIsLitWhole(text: String) throws {
        let pieces = text.split(separator: " ").map(String.init)
        let line = LyricLine(time: 1, words: pieces.enumerated().map { index, piece in
            LyricWord(text: index == pieces.count - 1 ? piece : piece + " ", begin: 1 + Double(index), end: 2 + Double(index))
        })
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        #expect(view.sweep == nil)
        #expect(view.litLayer.mask == nil)
        #expect(view.dimLayer.isHidden)
        #expect(!view.isAnimating)
        #expect(animation(view) == nil)
        #expect((view.litLayer.string as? String) == line.text)
        #expect(view.litLayer.foregroundColor == NSColor.white.cgColor)
    }

    @Test func aLeftToRightLineWithNumbersAndPunctuationStillSweeps() throws {
        let line = LyricLine(time: 1, words: [LyricWord(text: "Track 1: ", begin: 1, end: 2), LyricWord(text: "go!", begin: 2, end: 3)])
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        #expect(view.sweep != nil)
        #expect(view.isAnimating)
    }

    @Test func aLineThatLosesItsWordsToDirectionIsAWholeLineAgainWhenAnotherComes() throws {
        let view = makeView()
        let arabic = LyricLine(time: 1, words: [LyricWord(text: "مرحبا ", begin: 1, end: 2), LyricWord(text: "بالعالم", begin: 2, end: 3)])
        view.show(line: arabic, clock: clock(elapsed: 1.5), style: style)
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        #expect(view.litLayer.mask === view.fillMask)
        #expect(view.sweep != nil)
    }

    // MARK: the sweep's cost

    @Test func theAnimationIsAskedForAtMostSixtyFramesASecond() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        let keyframes = try #require(animation(view))
        #expect(keyframes.preferredFrameRateRange == CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60))
    }

    @Test func aViewWithNoWidthYetBuildsNothingAndTheFirstWidthBuildsOnce() {
        let view = KaraokeLineView(now: { origin })
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        #expect(view.buildCount == 0)
        view.isOnScreen = true
        view.isOnScreen = false
        view.isOnScreen = true
        #expect(view.buildCount == 0)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 16)
        #expect(view.buildCount == 1)
        #expect(view.isAnimating)
    }

    // MARK: VoiceOver

    @Test func theViewIsOneElementThatReadsTheLine() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityLabel() == "one two three")
        view.show(line: LyricLine(time: 6, text: "next"), clock: clock(elapsed: 6.5), style: style)
        #expect(view.accessibilityLabel() == "next")
    }

    // MARK: while the notch cannot be seen

    @Test func offScreenTheAnimationIsTakenAwayAndBackOnScreenItStartsAgainFromNow() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.isOnScreen = false
        #expect(animation(view) == nil)
        view.isOnScreen = true
        #expect(animation(view) != nil)
    }

    @Test func aLineShownWhileOffScreenIsNotAnimated() {
        let view = makeView()
        view.isOnScreen = false
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        #expect(animation(view) == nil)
        #expect(view.sweep != nil)
    }

    @Test func settingTheSameVisibilityAgainBuildsNothing() {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 1.5), style: style)
        view.isOnScreen = true
        view.isOnScreen = true
        #expect(view.buildCount == 1)
    }

    @Test func aChangeOfWidthPlacesTheTextAgainAndKeepsTheFillInStep() throws {
        let view = makeView()
        view.show(line: line, clock: clock(elapsed: 2.5, playing: false), style: style)
        view.frame = CGRect(x: 0, y: 0, width: 500, height: 16)
        view.layoutSubtreeIfNeeded()
        #expect(abs(view.litLayer.frame.midX - 250) < 0.5)
        let sweep = try #require(view.sweep)
        #expect(abs(Double(view.fillMask.position.x) - maskX(sweep.start, in: view)) < 1e-6)
    }
}

/// The SwiftUI side: the line in a hosting view that is not shown, with the run loop doing what the display would. A window
/// that is not shown has no render server to hold animations, so Core Animation drops them at the first commit: these tests
/// ask the view whether it has started one (`isAnimating`) and the layers' own tests in the suite above look at the animation.
@Suite struct KaraokeLineHostingTests {
    func playingStore(elapsed: Double = 1.2) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(elapsed: elapsed), receivedAt: Date())
        return store
    }

    let line = LyricLine(time: 1, words: [
        LyricWord(text: "one ", begin: 1, end: 2), LyricWord(text: "two ", begin: 2, end: 3), LyricWord(text: "three", begin: 3, end: 30),
    ])
    let style = KaraokeStyle(fontSize: 12, weight: .semibold, lit: .white, dim: .gray)

    func host<Content: View>(_ content: Content) -> (CountingHostingView<Content>, NSWindow) {
        let hosting = CountingHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func karaokeView(in view: NSView) -> KaraokeLineView? {
        if let found = view as? KaraokeLineView { return found }
        for subview in view.subviews { if let found = karaokeView(in: subview) { return found } }
        return nil
    }

    func run(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @Test func theLineSweepsInAViewOfItsOwnInsideTheHostingView() throws {
        let store = playingStore()
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16))
        run(for: 0.05)
        let view = try #require(karaokeView(in: hosting))
        #expect(view.isAnimating)
        window.contentView = nil
    }

    /// The point of the layer: the fill moves with no pass of SwiftUI's, so the notch never lays out for it.
    @Test func aLineMountedInTheHostingViewIsBuiltOnce() throws {
        let store = playingStore()
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(width: 300, height: 16))
        run(for: 0.05)
        let view = try #require(karaokeView(in: hosting))
        // Not at the width of 0 it is made at, and not again for what SwiftUI hands it unchanged.
        #expect(view.buildCount == 1)
        window.contentView = nil
    }

    @Test func theSweepNeverLaysTheHostingViewOutAgain() throws {
        let store = playingStore()
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16))
        run(for: 0.05)
        let layouts = hosting.layouts
        run(for: 0.3)
        #expect(hosting.layouts == layouts)
        #expect(!hosting.needsLayout)
        window.contentView = nil
    }

    @Test func aPauseReachesTheLayerAndTakesTheAnimationAway() throws {
        let store = playingStore()
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16))
        run(for: 0.05)
        let view = try #require(karaokeView(in: hosting))
        store.apply(line: AdapterLines.playing(false), receivedAt: Date())
        run(for: 0.1)
        #expect(!view.isAnimating)
        store.apply(line: AdapterLines.playing(true), receivedAt: Date())
        run(for: 0.1)
        #expect(view.isAnimating)
        window.contentView = nil
    }

    @Test func aSeekReachesTheLayer() throws {
        let store = playingStore(elapsed: 1.2)
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16))
        run(for: 0.05)
        let view = try #require(karaokeView(in: hosting))
        let before = try #require(view.sweep).start
        store.apply(line: AdapterLines.position(2.6), receivedAt: Date())
        run(for: 0.1)
        #expect(try #require(view.sweep).start > before)
        window.contentView = nil
    }

    @Test func aHiddenNotchStopsTheAnimation() throws {
        let store = playingStore()
        let (hosting, window) = host(KaraokeLine(line: line, store: store, style: style).frame(height: 16).environment(\.notchIsOnScreen, false))
        run(for: 0.05)
        let view = try #require(karaokeView(in: hosting))
        #expect(!view.isAnimating)
        window.contentView = nil
    }
}
