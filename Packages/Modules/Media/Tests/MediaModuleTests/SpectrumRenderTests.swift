import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

/// Counts the passes in which SwiftUI evaluates and lays out the views of a hosting view.
final class CountingHostingView<Content: View>: NSHostingView<Content> {
    private(set) var layouts = 0

    override func layout() {
        layouts += 1
        super.layout()
    }
}

/// The bars inside a hosting view in a window that is never shown, with the run loop doing what the display would.
@Suite struct SpectrumRenderTests {
    func playingStore() -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        return store
    }

    func host<Content: View>(_ content: Content) -> (CountingHostingView<Content>, NSWindow) {
        let hosting = CountingHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 120, height: 60), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func run(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// The point of the change: new levels from the tap used to invalidate a SwiftUI view, so the whole notch laid out for
    /// each of them, about 30 times a second.
    @Test func aSpectrumUpdateNeverLaysTheHostingViewOutAgain() {
        let store = playingStore()
        store.showSpectrum([0.2, 0.2, 0.2, 0.2])
        let (hosting, window) = host(NowPlayingBars(store: store))
        runLoopUntilQuiet { hosting.layouts }
        let size = hosting.fittingSize
        let layouts = hosting.layouts
        for step in 0..<12 {
            store.showSpectrum([Float(step) / 12, 0.5, 0.25, 1])
            run(for: 0.015)
        }
        #expect(hosting.layouts == layouts)
        #expect(!hosting.needsLayout)
        #expect(hosting.fittingSize == size)
        window.contentView = nil
    }

    /// The made-up motion used to be a TimelineView redrawing at 30 fps, with the same effect.
    @Test func theMadeUpMotionNeverLaysTheHostingViewOutAgain() {
        let store = playingStore()
        let (hosting, window) = host(NowPlayingBars(store: store))
        runLoopUntilQuiet { hosting.layouts }
        let layouts = hosting.layouts
        run(for: 0.2)
        #expect(hosting.layouts == layouts)
        #expect(!hosting.needsLayout)
        window.contentView = nil
    }

    func bars(in view: NSView) -> SpectrumBarsView? {
        if let bars = view as? SpectrumBarsView { return bars }
        for subview in view.subviews {
            if let bars = bars(in: subview) { return bars }
        }
        return nil
    }

    /// The tint changes the bars' layers and nothing SwiftUI draws: a new cover must not make the notch lay out either.
    @Test func aNewTintNeverLaysTheHostingViewOutAgain() throws {
        let store = playingStore()
        let (hosting, window) = host(NowPlayingBars(store: store))
        runLoopUntilQuiet { hosting.layouts }
        let view = try #require(bars(in: hosting))
        let layouts = hosting.layouts
        for step in 0..<3 {
            let before = view.layer?.sublayers?.first?.backgroundColor
            store.showTint(ArtworkPalette(primary: SRGBColor(red: 0.9, green: Double(step) / 3, blue: 0.1), secondary: nil))
            #expect(view.layer?.sublayers?.first?.backgroundColor != before, "the bars did take the colour")
            run(for: 0.02)
        }
        #expect(hosting.layouts == layouts)
        #expect(!hosting.needsLayout)
        window.contentView = nil
    }
}
