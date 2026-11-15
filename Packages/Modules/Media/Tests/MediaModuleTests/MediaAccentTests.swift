import AppKit
import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import MediaModule
@testable import NotchUI

/// A colour no module draws with, so a pass can only mean that the view took the accent it was given.
private let probeGreen = Color(.sRGB, red: 0, green: 1, blue: 0)
private let probeOrange = Color(.sRGB, red: 1, green: 0.5, blue: 0)

/// The colour of a layer as sRGB components, for comparing a colour that went through SwiftUI.
private func srgb(_ color: CGColor?) -> [Double]? {
    guard let color, let converted = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
    return [converted.redComponent, converted.greenComponent, converted.blueComponent].map { Double($0) }
}

private func isClose(_ color: CGColor?, to expected: Color) -> Bool {
    guard let actual = srgb(color) else { return false }
    let wanted = SRGBColor(expected)
    return zip(actual, [wanted.red, wanted.green, wanted.blue]).allSatisfy { abs($0 - $1) < 0.01 }
}

/// What a notch's environment says is the accent, changed by the test.
@Observable private final class AccentBox {
    var accent: Color
    init(_ accent: Color) { self.accent = accent }
}

private struct BarsInAccent: View {
    let box: AccentBox
    let store: NowPlayingStore

    var body: some View {
        SpectrumBars(store: store).environment(\.notchAccent, box.accent)
    }
}

/// What a view in a window of its own has for an accent, written down each time it is drawn.
private final class SeenAccent {
    var accent: Color?
}

private struct AccentProbe: View {
    @Environment(\.notchAccent) private var accent
    let seen: SeenAccent

    var body: some View {
        seen.accent = accent
        return Color.clear
    }
}

/// A window's root view as the lyrics panel has it: the accent is taken in its body, which is what redraws it.
private struct WindowRoot: View {
    let interface: NotchInterface
    let seen: SeenAccent

    var body: some View {
        AccentProbe(seen: seen).followingAccent(of: interface)
    }
}

/// The average colour of what is drawn, by opacity: an icon or a bar drawn in one colour gives that colour.
private func drawnColour(of view: some View) throws -> (red: Double, green: Double, blue: Double) {
    let renderer = ImageRenderer(content: view.padding(4))
    renderer.scale = 2
    let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    var total = (red: 0.0, green: 0.0, blue: 0.0, weight: 0.0)
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), pixel.alphaComponent > 0.5 else { continue }
            total.red += Double(pixel.redComponent)
            total.green += Double(pixel.greenComponent)
            total.blue += Double(pixel.blueComponent)
            total.weight += 1
        }
    }
    try #require(total.weight > 0, "something was drawn")
    return (total.red / total.weight, total.green / total.weight, total.blue / total.weight)
}

/// The accent the user picked, in every drawing of Media that is marked with it. Nothing here asks a view for the notch's
/// own purple: the view takes what its environment says.
@Suite struct MediaAccentTests {
    func playingStore() -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        return store
    }

    func bars(in view: NSView) -> SpectrumBarsView? {
        if let bars = view as? SpectrumBarsView { return bars }
        for subview in view.subviews {
            if let bars = bars(in: subview) { return bars }
        }
        return nil
    }

    func host<Content: View>(_ content: Content) -> (NSHostingView<Content>, NSWindow) {
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 120, height: 60), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func colours(_ view: SpectrumBarsView) -> [CGColor?] { view.layer?.sublayers?.map(\.backgroundColor) ?? [] }

    func run(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: the spectrum, which is layers

    @Test func theBarsTakeTheAccentTheirNotchHasAndFollowItWhenItChanges() throws {
        let box = AccentBox(probeGreen)
        let (hosting, window) = host(BarsInAccent(box: box, store: playingStore()))
        defer { window.contentView = nil }
        let view = try #require(bars(in: hosting))
        #expect(colours(view).allSatisfy { isClose($0, to: probeGreen) })
        box.accent = probeOrange
        #expect(runLoop(until: { colours(view).allSatisfy { isClose($0, to: probeOrange) } }, seconds: 5))
    }

    @Test func anAccentChangeIsNothingMoreThanOnePaintAndNeverAnimates() throws {
        let box = AccentBox(probeGreen)
        let (hosting, window) = host(BarsInAccent(box: box, store: playingStore()))
        defer { window.contentView = nil }
        let view = try #require(bars(in: hosting))
        let painted = view.paintCount
        box.accent = probeOrange
        #expect(runLoop(until: { view.paintCount > painted }, seconds: 5))
        runLoopUntilQuiet { view.paintCount }
        #expect(view.paintCount == painted + 1)
        #expect(view.layer?.sublayers?.allSatisfy { $0.animationKeys() == nil } == true)
    }

    /// The point of the layers: the bars move 30 times a second without SwiftUI, and the colour is not part of it.
    @Test func theTapsLevelsNeverPaintTheLayersAgain() throws {
        let store = playingStore()
        let (hosting, window) = host(BarsInAccent(box: AccentBox(probeGreen), store: store))
        defer { window.contentView = nil }
        let view = try #require(bars(in: hosting))
        runLoopUntilQuiet { view.paintCount }
        let painted = view.paintCount
        for step in 0..<12 {
            store.showSpectrum([Float(step) / 12, 0.5, 0.25, 1])
            run(for: 0.015)
        }
        #expect(view.paintCount == painted)
    }

    @Test func theSameAccentAgainPaintsNothing() throws {
        let box = AccentBox(probeGreen)
        let (hosting, window) = host(BarsInAccent(box: box, store: playingStore()))
        defer { window.contentView = nil }
        let view = try #require(bars(in: hosting))
        runLoopUntilQuiet { view.paintCount }
        let painted = view.paintCount
        box.accent = probeGreen
        run(for: 0.1)
        #expect(view.paintCount == painted)
    }

    @Test func theCoversColoursStillWinOverTheAccent() throws {
        let store = playingStore()
        let tint = ArtworkPalette(primary: SRGBColor(red: 0.9, green: 0.2, blue: 0.1), secondary: SRGBColor(red: 0.1, green: 0.4, blue: 0.9))
        store.showTint(tint)
        let box = AccentBox(probeGreen)
        let (hosting, window) = host(BarsInAccent(box: box, store: store))
        defer { window.contentView = nil }
        let view = try #require(bars(in: hosting))
        let covers = colours(view)
        #expect(!covers.contains { isClose($0, to: probeGreen) }, "the bars carry the cover's colours")
        let painted = view.paintCount
        box.accent = probeOrange
        run(for: 0.1)
        #expect(colours(view) == covers, "an accent that the bars do not use changes none of their colours")
        #expect(view.paintCount == painted, "and costs no paint")
    }

    @Test func whenTheCoverGoesAwayTheBarsTakeTheAccentOfNowNotTheOneTheyWereMadeWith() throws {
        let store = playingStore()
        store.showTint(ArtworkPalette(primary: SRGBColor(red: 0.9, green: 0.2, blue: 0.1), secondary: nil))
        let box = AccentBox(probeGreen)
        let (hosting, window) = host(BarsInAccent(box: box, store: store))
        defer { window.contentView = nil }
        let view = try #require(bars(in: hosting))
        box.accent = probeOrange
        run(for: 0.1)
        store.showTint(nil)
        #expect(colours(view).allSatisfy { isClose($0, to: probeOrange) })
    }

    // MARK: the views

    @Test func anActiveControlIsDrawnInTheEnvironmentsAccent() throws {
        let button = RowButton(symbol: "shuffle", label: "Ngẫu nhiên", symbolSize: 28, isActive: true, action: {})
        let green = try drawnColour(of: button.environment(\.notchAccent, probeGreen))
        #expect(green.green > 0.9 && green.red < 0.1 && green.blue < 0.1, "\(green)")
        let orange = try drawnColour(of: button.environment(\.notchAccent, probeOrange))
        #expect(orange.red > 0.9 && orange.blue < 0.1, "\(orange)")
    }

    @Test func anInactiveControlStaysTheTextColourWhateverTheAccentIs() throws {
        let button = RowButton(symbol: "shuffle", label: "Ngẫu nhiên", symbolSize: 28, isActive: false, action: {})
        let colour = try drawnColour(of: button.environment(\.notchAccent, probeGreen))
        #expect(colour.red > 0.8 && colour.green > 0.8 && colour.blue > 0.8, "\(colour)")
    }

    @Test func theLyricsPanelButtonIsDrawnInTheEnvironmentsAccentWhileThePanelIsUp() throws {
        let store = playingStore()
        store.setLyricsOn(true)
        store.setLyricsPanelShown(true)
        let row = CurrentLyricView(store: store).frame(width: 200, height: 20).environment(\.notchAccent, probeGreen)
        let colour = try drawnColour(of: row)
        #expect(colour.green > 0.9 && colour.red < 0.1 && colour.blue < 0.1, "\(colour)")
    }

    @Test func theProgressBarKeepsTheCoversColourOverTheAccentAndUsesTheAccentWithoutOne() {
        let tint = SRGBColor(red: 0.9, green: 0.2, blue: 0.1)
        #expect(PlaybackProgressView.fill(tint: nil, isActive: true, accent: probeGreen) == probeGreen)
        #expect(PlaybackProgressView.fill(tint: nil, isActive: false, accent: probeGreen) == NotchTokens.primaryText.opacity(0.85))
        #expect(PlaybackProgressView.fill(tint: tint, isActive: true, accent: probeGreen) == tint.color)
        #expect(PlaybackProgressView.fill(tint: tint, isActive: false, accent: probeGreen) == tint.color)
    }

    // MARK: the floating lyrics panel, a window of its own

    @Test func aWindowOfItsOwnTakesTheAccentOfTheInterfaceAndFollowsIt() throws {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let theme = NotchTheme(settings: settings, systemAccent: { .init(red: 10, green: 132, blue: 255) }, notifications: NotificationCenter())
        let interface = NotchInterface()
        let following = interface.follow(settings, theme: theme)
        defer { following.cancel() }
        settings.set(.palette(.green), for: InterfaceSettings.accent)
        let seen = SeenAccent()
        let (_, window) = host(WindowRoot(interface: interface, seen: seen))
        defer { window.contentView = nil }
        #expect(seen.accent == NotchAccent.Palette.green.rgb.color)
        settings.set(.palette(.orange), for: InterfaceSettings.accent)
        #expect(runLoop(until: { seen.accent == NotchAccent.Palette.orange.rgb.color }, seconds: 5))
    }
}
