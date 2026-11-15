import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import MediaModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct MediaGlassTests {
    struct Reading {
        let background: Double
        let pixels: [Double]
        func lighter(than margin: Double) -> Int { pixels.filter { $0 > background + margin }.count }
        func darker(than margin: Double) -> Int { pixels.filter { $0 < background - margin }.count }
    }

    func read(_ view: some View, glass: Bool, scheme: ColorScheme, size: CGSize) throws -> Reading {
        let state = NotchLookState()
        state.isGlass = glass
        let shade = !glass ? 0.0 : scheme == .light ? 0.75 : 0.15
        return try NotchLookState.$current.withValue(state) {
            @MainActor func lightness(of view: some View) throws -> [Double] {
                let content = view.frame(width: size.width, height: size.height).background(Color(.sRGB, white: shade))
                    .environment(\.colorScheme, scheme)
                    .environment(\.notchSurface, glass ? .liquidGlass(tinted: false) : .solid)
                let host = NSHostingView(rootView: content)
                host.frame = CGRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                // AppKit controls follow the window's appearance, not SwiftUI's colour scheme.
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                bitmap.size = size
                host.cacheDisplay(in: host.bounds, to: bitmap)
                var pixels: [Double] = []
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let colour = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        pixels.append(Double(min(colour.redComponent, colour.greenComponent, colour.blueComponent)))
                    }
                }
                return pixels
            }
            // The renderer lifts tones a little, so the background is what an empty picture reads, not the grey that was set.
            return Reading(background: try lightness(of: Color.clear)[0], pixels: try lightness(of: view))
        }
    }

    struct Fixture {
        let name: String
        let view: AnyView
        let size: CGSize
        /// How far above the background a pixel may be on light glass: a system control lifts its own fill a little. Nil where
        /// the view draws light on a dark fill of its own on purpose.
        let wash: Double?
        /// Pixels of ink the view draws: at least this many are `reach` or more away from the background.
        let ink: Int
        var reach = 0.3
        /// The appearances the classic notch is checked in: a view that draws with the system's colours has only the dark one.
        var classicSchemes: [ColorScheme] = [.dark, .light]
    }

    let timed = LyricLine(time: 10, words: [
        LyricWord(text: "one ", begin: 10, end: 11), LyricWord(text: "two ", begin: 11, end: 12), LyricWord(text: "three", begin: 12, end: 14),
    ])

    /// A paused track with a timed lyric line: nothing in it moves.
    func store(karaoke: Bool = true, lines: [LyricLine]? = nil) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(playing: false, elapsed: 10.5), receivedAt: Date())
        store.setLyricsOn(true)
        store.showLyrics(lines ?? [timed])
        store.setKaraokeEnabled(karaoke)
        return store
    }

    var actions: MediaActions { MediaActions(send: { _ in }, seek: { _ in }) }

    var fixtures: [Fixture] {
        let store = store()
        let volume = VolumeModel(hardware: NoVolumeHardware(), queue: ManualVolumeQueue())
        let presence = LyricsPanelPresence()
        presence.setWindowVisible(true)
        let tab = CGSize(width: 452, height: 150)
        return [
            Fixture(name: "player", view: AnyView(MediaTabView(store: store, actions: actions, volume: volume)), size: tab, wash: 0.005, ink: 150, reach: 0.15),
            Fixture(name: "lyric strip", view: AnyView(NowPlayingLyricStrip(store: store)), size: CGSize(width: 300, height: 40), wash: 0.005, ink: 50, reach: 0.15),
            // The panel and the lock screen's card are black on any look, so their light text is meant to be light.
            Fixture(name: "lyrics panel", view: AnyView(LyricsPanelView(store: store, model: LyricsPanelModel(fontSize: 22), presence: presence).frame(width: 420, height: 130)), size: CGSize(width: 420, height: 130), wash: nil, ink: 100, reach: 0.15),
            Fixture(name: "lock screen card", view: AnyView(lockScreenCard(store)), size: CGSize(width: 420, height: 110), wash: nil, ink: 100, reach: 0.15),
        ]
    }

    /// What the lock screen draws the media view on.
    func lockScreenCard(_ store: NowPlayingStore) -> some View {
        NowPlayingLockScreenView(transport: LockScreenTransport(store: store, actions: actions))
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NotchTokens.background)
    }

    @Test func theLyricsPanelKeepsLightTextOnItsDarkSurfaceOnLightGlass() throws {
        let presence = LyricsPanelPresence()
        presence.setWindowVisible(true)
        // Without the fill by word, so the three lines are text that follows the colour scheme, not layers with a colour of their own.
        let lines = [LyricLine(time: 5, text: "before"), LyricLine(time: 10, text: "current"), LyricLine(time: 20, text: "after")]
        let panel = LyricsPanelView(store: store(karaoke: false, lines: lines), model: LyricsPanelModel(fontSize: 22), presence: presence)
        let reading = try read(panel, glass: true, scheme: .light, size: CGSize(width: 420, height: 130))
        #expect(reading.lighter(than: 0.05) >= 100, "light lines on the panel's dark surface, not black on black")
    }

    @Test func theLockScreenCardKeepsLightTextOnItsBlackCardOnLightGlass() throws {
        let reading = try read(lockScreenCard(store()), glass: true, scheme: .light, size: CGSize(width: 420, height: 110))
        #expect(reading.lighter(than: 0.05) >= 100, "light title and lyrics on the black card, not black on black")
    }

    @Test func theLyricRowAndTheStripUseTheLabelColoursOnGlassAndWhiteOtherwise() {
        #expect(KaraokeStyle.row.lit == NSColor(Color.white).withAlphaComponent(0.9))
        #expect(KaraokeStyle.strip.lit == NSColor(Color.white))
        #expect(KaraokeStyle.stripOnGlass.dim == NSColor.secondaryLabelColor)
        // The row's colours are the label colours at a strength and stay dynamic: dark in a light appearance, light in a dark one.
        func red(_ colour: NSColor, in name: NSAppearance.Name) -> CGFloat {
            var red: CGFloat = -1
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance { red = colour.usingColorSpace(.sRGB)?.redComponent ?? -1 }
            return red
        }
        #expect(red(KaraokeStyle.rowOnGlass.lit, in: .aqua) < 0.35 && red(KaraokeStyle.rowOnGlass.lit, in: .darkAqua) > 0.65)
        #expect(red(KaraokeStyle.rowOnGlass.dim, in: .aqua) < 0.5 && red(KaraokeStyle.rowOnGlass.dim, in: .darkAqua) > 0.5)
        #expect(KaraokeStyle.lockScreen.lit == NSColor(Color.white), "the lock screen's card is black on any look")
    }

    @Test func aKaraokeLineWithTheSystemsColoursFollowsTheAppearanceItIsIn() {
        let view = KaraokeLineView()
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 16)
        let clock = KaraokeClock(NowPlayingState(
            bundleIdentifier: "x", title: "t", durationSeconds: 100,
            elapsedAnchor: PlaybackAnchor(elapsedSeconds: 10.5, timestamp: Date(timeIntervalSince1970: 8_000), rate: 1), isPlaying: false
        ))
        view.appearance = NSAppearance(named: .aqua)
        view.show(line: timed, clock: clock, style: .stripOnGlass)
        func litBrightness() -> CGFloat? {
            view.litLayer.foregroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB)?.redComponent }
        }
        let inLight = litBrightness()
        view.appearance = NSAppearance(named: .darkAqua)
        let inDark = litBrightness()
        #expect((inLight ?? 1) < 0.35, "dark text on light glass")
        #expect((inDark ?? 0) > 0.65, "light text on dark glass, made again when the appearance changed")
    }
    @Test func onLightGlassTheViewsDrawDarkAndNothingWhite() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: fixture.size)
            if let wash = fixture.wash {
                #expect(reading.lighter(than: wash) == 0, "\(fixture.name): something is drawn white on light glass")
            }
            #expect(reading.darker(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads dark")
        }
    }

    @Test func onDarkGlassTheViewsDrawLight() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .dark, size: fixture.size)
            #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads light")
        }
    }

    @Test func onTheClassicNotchTheViewsStayWhiteOnBlackWhateverTheAppearanceIs() throws {
        for fixture in fixtures {
            for scheme in fixture.classicSchemes {
                let reading = try read(fixture.view, glass: false, scheme: scheme, size: fixture.size)
                #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name) in \(scheme)")
            }
        }
    }
}
