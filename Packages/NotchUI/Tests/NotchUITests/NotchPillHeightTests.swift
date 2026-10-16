import AppKit
import CoreGraphics
import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import NotchUI

/// The pill's own height (`interface.pillHeight`): the setting, what the geometry makes of it, and that the collapsed notch's content stays
/// centred in a taller body.
@Suite struct NotchPillHeightTests {
    let external = NotchGeometryTests.external
    let gap = NotchGeometry.pillTopGap

    func pill(_ height: CGFloat, width: CGFloat = 185) -> NotchGeometry {
        NotchGeometry(screen: external, config: NotchLayoutConfig(virtualNotchWidth: width, virtualNotchStyle: .pill, pillHeight: height))
    }

    // MARK: the setting

    @Test func theKeyTheDefaultAndTheRangeAre32From24To56() {
        #expect(InterfaceSettings.pillHeight.name == "interface.pillHeight")
        #expect(NotchGeometry.pillHeightLimits == 24...56)
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(settings.value(InterfaceSettings.pillHeight) == 32)
        #expect(NotchLayoutConfig().pillHeight == 32)
        #expect(NotchLayoutConfig(settings: settings).pillHeight == 32)
    }

    @Test func aHeightIsKeptForTheNextLaunchAndResetGoesBackToTheDefault() {
        let defaults = makeIsolatedDefaults()
        for height in [24.0, 33, 48, 56] {
            SettingsStore(defaults: defaults).set(height, for: InterfaceSettings.pillHeight)
            #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.pillHeight) == height)
        }
        let settings = SettingsStore(defaults: defaults)
        settings.reset(InterfaceSettings.pillHeight)
        #expect(settings.value(InterfaceSettings.pillHeight) == 32)
    }

    @Test func aHeightOutsideTheRangeIsHeldToItWhenSetAndWhenStored() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        for (set, read) in [(10.0, 24.0), (23.9, 24), (24, 24), (56, 56), (56.1, 56), (500, 56), (-3, 24)] {
            settings.set(set, for: InterfaceSettings.pillHeight)
            #expect(settings.value(InterfaceSettings.pillHeight) == read, "\(set)")
        }
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("90".utf8), forKey: InterfaceSettings.pillHeight.name)
        #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.pillHeight) == 56)
        for garbage in ["\"tall\"", "true", "null", "not json"] {
            let defaults = makeIsolatedDefaults()
            defaults.set(Data(garbage.utf8), forKey: InterfaceSettings.pillHeight.name)
            #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.pillHeight) == 32, Comment(rawValue: garbage))
        }
    }

    @Test func aChangeOfTheHeightReachesTheLoopThatRedrawsTheNotchesAndLeavesTheOtherSettingsAlone() async {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        final class Seen { var heights: [CGFloat] = [] }
        let seen = Seen()
        let loop = Task {
            for await config in Observations({ NotchLayoutConfig(settings: settings) }) { seen.heights.append(config.pillHeight) }
        }
        defer { loop.cancel() }
        func eventually(_ condition: () -> Bool) async -> Bool {
            for _ in 0..<400 {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(5))
            }
            return condition()
        }
        #expect(await eventually { seen.heights.last == 32 })
        settings.set(48, for: InterfaceSettings.pillHeight)
        #expect(await eventually { seen.heights.last == 48 })
        var config = NotchLayoutConfig(settings: settings)
        config.pillHeight = 32
        #expect(config == NotchLayoutConfig(settings: SettingsStore(defaults: makeIsolatedDefaults())))
    }

    // MARK: the geometry

    @Test func aPillIsAsTallAsItsSettingHeldToTheRange() {
        for (asked, height) in [(CGFloat(24), CGFloat(24)), (32, 32), (40, 40), (48, 48), (56, 56), (10, 24), (80, 56), (-5, 24)] {
            let geometry = pill(asked)
            #expect(geometry.notchSize == CGSize(width: 185, height: height), "\(asked)")
            #expect(geometry.shapeSize(for: .closed) == CGSize(width: 185, height: height))
            #expect(geometry.topGap == gap, "the same gap whatever the height")
        }
    }

    @Test func theCornerRadiusIsHalfTheHeightAndTheBubblesAreAsTall() {
        for height in [CGFloat(24), 32, 41, 56] {
            let geometry = pill(height)
            #expect(geometry.cornerRadii(for: .closed).bottom == height / 2)
            #expect(geometry.shape(for: .closed) == NotchShape(topRadius: 0, bottomRadius: height / 2, cornerRadius: height / 2))
            // A strip under the pill does not change the radius.
            #expect(geometry.shape(for: .compact).cornerRadius == height / 2)
            #expect(geometry.bubbleDiameter == height)
            for index in 0..<NotchGeometry.maxBubbles {
                let bubble = geometry.bubbleFrame(at: index)
                #expect(bubble.height == height && bubble.minY == gap, "as tall as the pill and level with it: centred")
                #expect(bubble.midY == gap + height / 2)
            }
        }
    }

    @Test func theHitAreaTheHoverZoneAndThePanelFollowTheHeight() {
        for height in [CGFloat(24), 32, 56] {
            let geometry = pill(height)
            let frame = external.frame
            #expect(geometry.hitRect(for: .closed, in: frame).height == gap + height + NotchGeometry.hitPadding + 1)
            #expect(geometry.hitRect(for: .closed, in: frame).minY == frame.maxY - gap - height - NotchGeometry.hitPadding)
            let low = CGPoint(x: frame.midX, y: frame.maxY - gap - height + 1)
            let under = CGPoint(x: frame.midX, y: frame.maxY - gap - height - NotchGeometry.hitPadding - 2)
            #expect(geometry.pointerZone(at: low, state: .closed, in: frame) == .notch, "the bottom of the pill, whatever its height")
            #expect(geometry.pointerZone(at: under, state: .closed, in: frame) == .outside)
            #expect(geometry.pointerZone(at: CGPoint(x: frame.midX, y: frame.maxY), state: .closed, in: frame) == .notch, "the top edge still opens it")
            #expect(geometry.panelSize == CGSize(width: 900, height: gap + height + 240))
            // The panel holds the tallest pill with the tallest list under it, and the open notch.
            let panel = geometry.panelFrame(in: frame)
            for (state, bottom) in [(NotchState.compact, geometry.listHeight(rows: NotchGeometry.maxListRows)), (.open(nil), 0), (.toast, 0)] {
                let size = geometry.shapeSize(for: state, contentHeight: 240, bottomHeight: bottom)
                let rect = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - gap - size.height, width: size.width, height: size.height)
                #expect(panel.contains(rect), "\(height) \(state)")
            }
            // The open pill still grows downward from it.
            #expect(geometry.shapeSize(for: .open(nil), contentHeight: 120).height > height)
        }
    }

    @Test func aNotchIgnoresThePillHeightAndKeepsItsOwnRange() {
        for pillHeight in [CGFloat(24), 56] {
            let config = NotchLayoutConfig(virtualNotchStyle: .notch, pillHeight: pillHeight)
            #expect(NotchGeometry(screen: external, config: config).notchSize.height == 25, "the menu bar's, as it was")
            #expect(NotchGeometry(screen: external, config: NotchLayoutConfig(virtualNotchHeight: 36, virtualNotchStyle: .notch, pillHeight: pillHeight)).notchSize.height == 36)
        }
        // The notch's own range is 24 to 40.
        for (asked, height) in [(CGFloat(10), CGFloat(24)), (60, 40)] {
            #expect(NotchGeometry(screen: external, config: NotchLayoutConfig(virtualNotchHeight: asked)).notchSize.height == height)
        }
    }

    @Test func aPillIgnoresTheNotchHeightAndTheMenuBarMatch() {
        for notchHeight in [CGFloat?.none, 24, 40] {
            let geometry = NotchGeometry(
                screen: external, config: NotchLayoutConfig(virtualNotchHeight: notchHeight, virtualNotchStyle: .pill, pillHeight: 48)
            )
            #expect(geometry.notchSize.height == 48, "\(String(describing: notchHeight))")
        }
    }

    @Test func aHardwareNotchIsNeverAffected() {
        let book = NotchGeometryTests.macBook14
        let plain = NotchGeometry(screen: book, config: NotchLayoutConfig())
        for height in [CGFloat(24), 56] {
            let geometry = NotchGeometry(screen: book, config: NotchLayoutConfig(virtualNotchStyle: .pill, pillHeight: height))
            #expect(geometry.notchSize == plain.notchSize && geometry.panelSize == plain.panelSize)
            #expect(geometry.collapsedContentScale == 1)
        }
    }

    // MARK: the content grows a little with the height

    @Test func theCollapsedContentIsBiggerOnATallPillAndNeverBloated() {
        #expect(pill(24).collapsedContentScale == 1)
        #expect(pill(32).collapsedContentScale == 1, "as it was up to 32 pt")
        #expect(pill(56).collapsedContentScale == 1.25, "a quarter bigger at the tallest")
        #expect(abs(pill(44).collapsedContentScale - 1.125) < 1e-9)
        var last: CGFloat = 0
        for height in stride(from: CGFloat(24), through: 56, by: 2) {
            let scale = pill(height).collapsedContentScale
            #expect(scale >= last && scale >= 1 && scale <= 1.25, "\(height)")
            last = scale
        }
        // A notch, on a display without a cutout or with one, is drawn as it was.
        #expect(NotchGeometry(screen: external, config: NotchLayoutConfig(virtualNotchHeight: 40)).collapsedContentScale == 1)
        #expect(NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig()).collapsedContentScale == 1)
    }
}

// MARK: the drawn view

private final class CentreProbe {
    var leading: CGRect?
    var trailing: CGRect?
    var strip: CGRect?
}

private struct Probe: View {
    let report: (CGRect) -> Void
    let size: CGSize
    var body: some View {
        Color.clear.frame(width: size.width, height: size.height)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report($0) }
    }
}

@Suite struct NotchPillCentringTests {
    fileprivate func host(_ geometry: NotchGeometry, look: NotchLook = .classic, shape: NotchGlassShape = .slab) async throws -> (CentreProbe, NSHostingView<NotchRootView>, NSWindow) {
        let harness = RegistryHarness([])
        await harness.registry.bootstrap()
        harness.settings.set(look, for: InterfaceSettings.look)
        harness.settings.set(shape, for: InterfaceSettings.glassShape)
        let theme = NotchTheme(settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let probe = CentreProbe()
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        model.hasActivity = true
        harness.activities.set(
            LiveActivity(
                id: "a",
                leading: AnyView(Probe(report: { probe.leading = $0 }, size: CGSize(width: 16, height: 16))),
                trailing: AnyView(Probe(report: { probe.trailing = $0 }, size: CGSize(width: 18, height: 12))),
                bottom: AnyView(Probe(report: { probe.strip = $0 }, size: CGSize(width: 100, height: 30))), bottomHeight: 36, summary: "a"
            ),
            from: "m"
        )
        let hosting = NSHostingView(
            rootView: NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
        )
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        for _ in 0..<300 {
            hosting.layoutSubtreeIfNeeded()
            if probe.leading != nil, probe.trailing != nil, probe.strip != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()
        return (probe, hosting, window)
    }

    @Test func theLeadingTrailingAndTheStripStayCentredInTheBodyOfAPillOfAnyHeight() async throws {
        for height in [CGFloat(24), 32, 40, 56] {
            for (look, shape) in [(NotchLook.classic, NotchGlassShape.slab), (.liquidGlass, .slab), (.liquidGlass, .tiles)] {
                let geometry = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill, opensAsTiles: shape == .tiles && look == .liquidGlass, pillHeight: height))
                let (probe, _, window) = try await host(geometry, look: look, shape: shape)
                defer { window.contentView = nil }
                let middle = geometry.topGap + height / 2
                let leading = try #require(probe.leading), trailing = try #require(probe.trailing), strip = try #require(probe.strip)
                #expect(abs(leading.midY - middle) < 0.01, "\(height) \(look) \(shape): leading \(leading.midY) against \(middle)")
                #expect(abs(trailing.midY - middle) < 0.01, "\(height) \(look) \(shape): trailing \(trailing.midY) against \(middle)")
                // (The strip's view is 30 pt in a strip of 36, which it is centred in.)
                #expect(abs(strip.minY - (geometry.topGap + height + 3)) < 0.01, "\(height) \(look) \(shape): the strip starts under the body: \(strip.minY)")
                #expect(abs(leading.midX - (geometry.panelSize.width / 2 - geometry.compactWidth / 2 + geometry.config.compactSideWidth / 2)) < 0.01, "at the pill's left end")
            }
        }
    }

    @Test func aNotchIsCentredTooAndItsContentIsAsItWas() async throws {
        let geometry = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchHeight: 40))
        let (probe, _, window) = try await host(geometry)
        defer { window.contentView = nil }
        let leading = try #require(probe.leading)
        #expect(abs(leading.midY - 20) < 0.01)
        #expect(leading.size == CGSize(width: 16, height: 16))
    }
}
