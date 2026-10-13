import AppKit
import Foundation
import Testing
@testable import MediaModule

@Suite struct NowPlayingStoreTests {
    /// Base64 PNG of a `size`×`size` image, so two sizes give two different artworks.
    static func png(size: Int) -> String {
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return image.representation(using: .png, properties: [:])!.base64EncodedString()
    }

    final class Lookups {
        var requested: [String] = []
        var apps: [String: PlayerApp] = [:]
    }

    func makeStore(_ lookups: Lookups = Lookups()) -> NowPlayingStore {
        NowPlayingStore { bundleID in
            lookups.requested.append(bundleID)
            return lookups.apps[bundleID]
        }
    }

    @Test func appliesAdapterLines() {
        let store = makeStore()
        #expect(store.apply(line: AdapterLines.track("Song", artist: "Artist"), receivedAt: Date()))
        #expect(store.state.title == "Song")
        #expect(store.state.artist == "Artist")
        #expect(store.state.isPlaying)
        #expect(!store.apply(line: #"{"type":"other"}"#, receivedAt: Date()))
        #expect(!store.apply(line: "not json", receivedAt: Date()))
        #expect(store.state.title == "Song")
    }

    @Test func decodesArtworkOnlyWhenItChanges() throws {
        let store = makeStore()
        #expect(store.artworkImage == nil)
        store.apply(line: AdapterLines.track(artworkBase64: Self.png(size: 2)), receivedAt: Date())
        let first = try #require(store.artworkImage)
        #expect(first.representations.first?.pixelsWide == 2)

        store.apply(line: AdapterLines.playing(false), receivedAt: Date())
        store.apply(line: AdapterLines.position(40), receivedAt: Date())
        #expect(store.artworkImage === first)

        store.apply(line: AdapterLines.diff(["artworkData": Self.png(size: 3)]), receivedAt: Date())
        let second = try #require(store.artworkImage)
        #expect(second !== first)
        #expect(second.representations.first?.pixelsWide == 3)

        store.apply(line: AdapterLines.diff(["artworkData": NSNull()]), receivedAt: Date())
        #expect(store.artworkImage == nil)
    }

    @Test func undecodableArtworkGivesNoImage() {
        let store = makeStore()
        store.apply(line: AdapterLines.track(artworkBase64: "AQID"), receivedAt: Date())
        #expect(store.state.artwork != nil)
        #expect(store.artworkImage == nil)
    }

    @Test func prefersTheParentAppForHelperProcesses() {
        let lookups = Lookups()
        let icon = NSImage(size: NSSize(width: 1, height: 1))
        lookups.apps = [
            "com.example.Browser": PlayerApp(name: "Browser", icon: icon),
            "com.example.Browser.helper": PlayerApp(name: "Browser Helper", icon: icon),
        ]
        let store = makeStore(lookups)
        store.apply(line: AdapterLines.track(bundle: "com.example.Browser.helper", parent: "com.example.Browser"), receivedAt: Date())
        #expect(store.appName == "Browser")
        #expect(store.appIcon === icon)
        #expect(lookups.requested == ["com.example.Browser"])
    }

    @Test func fallsBackToThePlayingBundleAndLooksUpOncePerApp() {
        let lookups = Lookups()
        lookups.apps = ["com.example.Player": PlayerApp(name: "Player", icon: NSImage(size: NSSize(width: 1, height: 1)))]
        let store = makeStore(lookups)
        store.apply(line: AdapterLines.track(bundle: "com.example.Player", parent: "com.example.Missing"), receivedAt: Date())
        #expect(store.appName == "Player")
        #expect(lookups.requested == ["com.example.Missing", "com.example.Player"])

        store.apply(line: AdapterLines.position(50), receivedAt: Date())
        store.apply(line: AdapterLines.track("Next", bundle: "com.example.Player", parent: "com.example.Missing"), receivedAt: Date())
        #expect(lookups.requested.count == 2)

        store.apply(line: AdapterLines.empty, receivedAt: Date())
        #expect(store.appName == nil)
        #expect(store.appIcon == nil)
    }

    @Test func positionFollowsThePlaybackClock() {
        let store = makeStore()
        let now = Date()
        store.apply(line: AdapterLines.track(elapsed: 30), receivedAt: now)
        #expect(store.position(at: now + 10).map { abs($0 - 40) < 0.01 } == true)
        #expect(makeStore().position(at: now) == nil)
    }

    @Test func failureClearsPlaybackAndResetForgetsIt() throws {
        let store = makeStore()
        store.apply(line: AdapterLines.track(artworkBase64: Self.png(size: 2)), receivedAt: Date())
        store.fail(message: "Blocked")
        #expect(store.failureMessage == "Blocked")
        #expect(store.state == .empty)
        #expect(store.artworkImage == nil)

        store.reset()
        #expect(store.failureMessage == nil)
        // A fresh reducer numbers artwork from 1 again; the store must still decode it.
        store.apply(line: AdapterLines.track(artworkBase64: Self.png(size: 2)), receivedAt: Date())
        #expect(store.artworkImage != nil)
    }
}
