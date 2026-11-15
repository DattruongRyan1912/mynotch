import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import Observation
import SwiftUI
import Testing
@testable import MediaModule

/// What a notch's root view says it is drawn on, changed by the test.
@Observable private final class SurfaceBox {
    var surface: NotchSurface
    init(_ surface: NotchSurface) { self.surface = surface }
}

private struct OnSurface<Content: View>: View {
    let box: SurfaceBox
    let content: Content

    var body: some View {
        content.environment(\.notchSurface, box.surface)
    }
}

/// The surface reaching the bars in both places they are drawn: in the collapsed notch's activity, and in the open Media tab.
@Suite final class SpectrumSurfaceTests {
    let source = FakeNowPlayingSource()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL
    let glass = NotchSurface.liquidGlass(tinted: false)

    init() {
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil },
            volume: VolumeModel(hardware: FakeVolumeHardware(level: 0.4), queue: ManualVolumeQueue())
        )
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit { try? FileManager.default.removeItem(at: storageBase) }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
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
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 80), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func edge(_ view: SpectrumBarsView) -> [Float] { view.layer?.sublayers?.map(\.shadowOpacity) ?? [] }

    /// The collapsed notch's activity, as the module publishes it for a track that is playing.
    func collapsedActivity() async throws -> AnyView {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        await settle { harness.activities.current != nil }
        return try #require(harness.activities.current?.activity.trailing)
    }

    /// The bars at the right of the player's controls in the open tab.
    func tabControls() -> MediaControlsRow {
        MediaControlsRow(
            store: module.store, actions: MediaActions(send: { _ in }, seek: { _ in }),
            volume: VolumeModel(hardware: FakeVolumeHardware(level: 0.4), queue: ManualVolumeQueue())
        )
    }

    @Test func theCollapsedNotchsBarsGetTheSurfaceTheNotchIsDrawnOn() async throws {
        let activity = try await collapsedActivity()
        for surface in [NotchSurface.solid, .material, glass] {
            let (hosting, window) = host(activity.environment(\.notchSurface, surface))
            defer { window.contentView = nil }
            let view = try #require(bars(in: hosting))
            #expect(view.surface == surface)
            #expect(edge(view) == Array(repeating: surface.isLiquidGlass ? 0.35 : 0, count: 4))
        }
    }

    @Test func theTabsBarsGetTheSurfaceTheNotchIsDrawnOn() throws {
        module.store.apply(line: AdapterLines.track(), receivedAt: Date())
        for surface in [NotchSurface.solid, .material, glass] {
            let (hosting, window) = host(tabControls().environment(\.notchSurface, surface))
            defer { window.contentView = nil }
            let view = try #require(bars(in: hosting))
            #expect(view.surface == surface)
            #expect(edge(view) == Array(repeating: surface.isLiquidGlass ? 0.35 : 0, count: 4))
        }
    }

    @Test func aBarsViewBeforeAnyNotchHasTheBlackOfTheClassicNotch() throws {
        let (hosting, window) = host(NowPlayingBars(store: module.store))
        defer { window.contentView = nil }
        #expect(try #require(bars(in: hosting)).surface == .solid)
    }

    @Test func theBarsFollowTheNotchWhenItsSurfaceChangesUnderThem() async throws {
        module.store.showTint(ArtworkPalette(primary: SRGBColor(hex: 0x5A1010), secondary: nil))
        let box = SurfaceBox(.solid)
        let glass = glass
        let (hosting, window) = host(OnSurface(box: box, content: NowPlayingBars(store: module.store)))
        defer { window.contentView = nil }
        let view = try #require(bars(in: hosting))
        #expect(edge(view) == [0, 0, 0, 0])
        let onBlack = view.layer?.sublayers?.first?.backgroundColor
        box.surface = glass
        #expect(runLoop(until: { view.surface == glass }, seconds: 5))
        #expect(edge(view) == [0.35, 0.35, 0.35, 0.35])
        #expect(view.layer?.sublayers?.first?.backgroundColor != onBlack, "the glass asks for a lighter colour than black does")
        box.surface = .material
        #expect(runLoop(until: { view.surface == .material }, seconds: 5))
        #expect(edge(view) == [0, 0, 0, 0])
    }
}
