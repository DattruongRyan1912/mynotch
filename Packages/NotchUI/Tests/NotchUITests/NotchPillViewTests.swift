import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

// MARK: a hosted notch on a display without a notch

private final class PillProbe {
    var frame: CGRect?
    var plan: NotchGlassPlan?
    /// How many times the tab's content appeared: it is not rebuilt when the notch's geometry changes.
    var appeared = 0
    /// Where a toast's content is, when one is shown.
    var toast: CGRect?
}

private struct PillTab: View {
    let probe: PillProbe
    @Environment(\.notchGlassPlan) private var plan

    var body: some View {
        let _ = (probe.plan = plan)
        Color.clear
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [probe] in probe.frame = $0 }
            .onAppear { [probe] in probe.appeared += 1 }
    }
}

private final class PillModule: FeatureModule {
    let descriptor: ModuleDescriptor
    let probe: PillProbe?
    let height: CGFloat
    init(_ id: ModuleID, order: Int, probe: PillProbe?, height: CGFloat = 190) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: true, order: order)
        self.probe = probe
        self.height = height
    }
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: descriptor.displayName, systemImage: "circle", preferredHeight: height,
            content: probe.map { AnyView(PillTab(probe: $0)) } ?? AnyView(Color.clear)
        )
    }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

/// The real root view hosted in a window that is never shown, on `NotchGeometryTests.external`, with one tab ("probe") that reports its
/// frame and the glass plan it sees. The settings are the theme's, so they can change while it is hosted, and `show(_:)` swaps the
/// root view for one of another geometry, as the window controller does when the interface settings change.
@MainActor private struct HostedPill {
    let hosting: NSHostingView<NotchRootView>
    let window: NSWindow
    let probe: PillProbe
    let model: NotchViewModel
    let settings: SettingsStore
    let harness: RegistryHarness
    let theme: NotchTheme
    /// Whether the open notch is made of tiles, which makes it taller by their chrome, as the window controller's geometry does.
    let tiles: Bool
    let pillHeight: CGFloat

    static func screenGeometry(
        _ style: VirtualNotchStyle, on screen: ScreenDescriptor = NotchGeometryTests.external, tiles: Bool = false, pillHeight: CGFloat = 32
    ) -> NotchGeometry {
        NotchGeometry(screen: screen, config: NotchLayoutConfig(virtualNotchStyle: style, opensAsTiles: tiles, pillHeight: pillHeight))
    }

    static func make(
        _ style: VirtualNotchStyle, on screen: ScreenDescriptor = NotchGeometryTests.external, look: NotchLook = .classic,
        clarity: NotchGlassClarity = .balanced, shape: NotchGlassShape = .slab, tabs: Int = 1, opened: Bool = true, height: CGFloat = 190,
        pillHeight: CGFloat = 32
    ) async throws -> HostedPill {
        let probe = PillProbe()
        let modules = [PillModule("probe", order: 0, probe: probe, height: height)]
            + (1..<max(tabs, 1)).map { PillModule(ModuleID(stringLiteral: "other\($0)"), order: $0, probe: nil) }
        let harness = RegistryHarness(modules)
        await harness.registry.bootstrap()
        harness.settings.set(look, for: InterfaceSettings.look)
        harness.settings.set(clarity, for: InterfaceSettings.glassClarity)
        harness.settings.set(shape, for: InterfaceSettings.glassShape)
        let theme = NotchTheme(settings: harness.settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let model = NotchViewModel(
            scheduler: harness.scheduler, availableTabs: { [registry = harness.registry] in registry.tabs.map(\.id) }, delays: { (.zero, .zero) }
        )
        let tiles = look == .liquidGlass && shape == .tiles
        let geometry = screenGeometry(style, on: screen, tiles: tiles, pillHeight: pillHeight)
        let hosting = NSHostingView(
            rootView: NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme)
        )
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: geometry.panelSize), styleMask: .borderless, backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        let host = HostedPill(
            hosting: hosting, window: window, probe: probe, model: model, settings: harness.settings, harness: harness, theme: theme, tiles: tiles,
            pillHeight: pillHeight
        )
        if opened {
            model.open(tab: "probe")
            try #require(model.displayState == .open("probe"))
            try await host.wait("the tab was laid out") { probe.frame != nil }
            try await host.settle()
        } else {
            hosting.layoutSubtreeIfNeeded()
        }
        return host
    }

    func close() { window.contentView = nil }

    /// What the window controller does when the geometry changes: a new root view of the new geometry, and a panel of the new size.
    func show(_ style: VirtualNotchStyle, on screen: ScreenDescriptor = NotchGeometryTests.external) {
        let geometry = Self.screenGeometry(style, on: screen, tiles: tiles, pillHeight: pillHeight)
        hosting.rootView = NotchRootView(
            model: model, activities: harness.activities, registry: harness.registry, geometry: geometry, theme: theme
        )
        window.setContentSize(geometry.panelSize)
        hosting.frame = CGRect(origin: .zero, size: geometry.panelSize)
    }

    func wait(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            hosting.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        hosting.layoutSubtreeIfNeeded()
        try #require(condition(), "gave up waiting: \(what)")
    }

    /// Waits until the tab has not moved for 100 ms: the notch springs as it opens, and when its style changes.
    func settle() async throws {
        var last: CGRect?
        var still = 0
        for _ in 0..<1000 {
            hosting.layoutSubtreeIfNeeded()
            if let value = probe.frame, value == last { still += 1 } else { still = 0 }
            if still >= 10 { return }
            last = probe.frame
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(Bool(false), "gave up waiting: the tab to settle")
    }

    /// The alpha of the pixel at `point` (from the panel's top left) of what the hosting view draws by itself; a window lets a click
    /// fall through where it is fully transparent. Glass is not drawn offscreen, so what shows is what SwiftUI itself draws.
    func alpha(at point: CGPoint) throws -> Double {
        let bounds = hosting.bounds
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: bounds))
        hosting.cacheDisplay(in: bounds, to: rep)
        let scale = Double(rep.pixelsWide) / bounds.width
        let color = try #require(rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
        return Double(color.alphaComponent)
    }
}

/// The pill in the real root view: the gap, the width of the content, the glass it draws from, and the switch between the styles while it
/// is open.
@Suite struct NotchPillViewTests {
    let gap = NotchGeometry.pillTopGap
    /// Every look and shape the pill has to work with, as (look, clarity, shape).
    static let looks: [(NotchLook, NotchGlassClarity, NotchGlassShape)] = [
        (.classic, .balanced, .slab), (.liquidGlass, .balanced, .slab), (.liquidGlass, .clear, .slab),
        (.liquidGlass, .balanced, .tiles), (.liquidGlass, .clear, .tiles),
    ]

    func tab(_ style: VirtualNotchStyle, _ look: (NotchLook, NotchGlassClarity, NotchGlassShape), tabs: Int = 2) async throws -> (CGRect, NotchGlassPlan?) {
        let host = try await HostedPill.make(style, look: look.0, clarity: look.1, shape: look.2, tabs: tabs)
        defer { host.close() }
        return (try #require(host.probe.frame), host.probe.plan)
    }

    // MARK: the open pill, drawn

    @Test func theOpenPillIsTheGapLowerAndAsTallAsTheNotchOnEveryLookAndShape() async throws {
        for look in Self.looks {
            for tabs in [1, 2] {
                let (notch, _) = try await tab(.notch, look, tabs: tabs)
                let (pill, _) = try await tab(.pill, look, tabs: tabs)
                let name = "\(look) \(tabs) tabs"
                // With tiles and several tabs the pill's capsule is the pill, so the tile is where the pill's height and the gap put it;
                // everywhere else the gap, and nothing else, moves the pill down.
                let tilesWithABar = look.0 == .liquidGlass && look.2 == .tiles && tabs >= 2
                if !tilesWithABar {
                    #expect(abs(pill.minY - notch.minY - gap) < 0.01, "\(name): the gap, and nothing else, moves it down (\(notch) -> \(pill))")
                    #expect(abs(pill.maxY - notch.maxY - gap) < 0.01, "\(name): it is as tall")
                }
                #expect(abs(pill.height - notch.height) < 0.01, "\(name): the tab has the same room")
                #expect(abs(pill.midX - HostedPill.screenGeometry(.pill).panelSize.width / 2) < 0.5, "\(name): centred \(pill)")
                // No ears: only the padding insets the content sideways, 8 pt less than the notch's ear and padding.
                #expect(abs(pill.width - notch.width - 8 * 2) < 0.01, "\(name): \(notch.width) -> \(pill.width)")
            }
        }
    }

    @Test func theTabIsWhereTheGeometrySaysThePaddingUnderTheGap() async throws {
        let (frame, _) = try await tab(.pill, (.classic, .balanced, .slab), tabs: 1)
        let geometry = HostedPill.screenGeometry(.pill)
        let bodyBottom = geometry.topGap + NotchTokens.padding
        #expect(abs(frame.minY - bodyBottom) < 0.01, "\(frame)")
        #expect(abs(frame.minX - (geometry.panelSize.width / 2 - 300 + NotchTokens.padding)) < 0.01)
        #expect(abs(frame.maxY - (geometry.topGap + geometry.shapeSize(for: .open(nil), contentHeight: 190).height - NotchTokens.padding)) < 0.01)
    }

    @Test func thePillDrawsFromTheGlassPlanTheNotchDoes() async throws {
        for look in Self.looks where look.0 == .liquidGlass {
            let (_, notch) = try await tab(.notch, look)
            let (_, pill) = try await tab(.pill, look)
            let plan = try #require(pill)
            #expect(plan == notch, "\(look)")
            #expect(plan.blursUnder == (look.1 == .clear), "the clear glass has the material under it on the pill too")
            #expect(plan.usesContainer)
            #expect(plan.shape == look.2)
            #expect(look.2 == .tiles ? plan.tiles?.isOpen == true && !plan.panelHasGlass : plan.panelHasGlass)
        }
    }

    // MARK: the toast is where the geometry says

    func measuredToast(_ geometry: NotchGeometry) throws -> CGRect {
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        model.showToast(AnyView(Color(.sRGB, red: 1, green: 0, blue: 0)), duration: .seconds(60))
        let view = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry)
            .frame(width: geometry.panelSize.width, height: geometry.panelSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y), color.redComponent > 0.9, color.greenComponent < 0.1 else { continue }
                (minX, maxX, minY, maxY) = (min(minX, x), max(maxX, x), min(minY, y), max(maxY, y))
            }
        }
        try #require(maxX >= 0, "the toast's colour is drawn")
        let screen = NotchGeometryTests.external.frame
        let panel = geometry.panelFrame(in: screen)
        return CGRect(x: panel.minX + CGFloat(minX), y: panel.maxY - CGFloat(maxY + 1), width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
    }

    @Test func theContentFrameIsWhereTheViewReallyPutsAToastOnAPill() throws {
        for config in [
            NotchLayoutConfig(virtualNotchStyle: .pill),
            NotchLayoutConfig(virtualNotchWidth: 240, openWidth: 700, virtualNotchStyle: .pill),
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, openWidth: 480, virtualNotchStyle: .pill),
        ] {
            let geometry = NotchGeometry(screen: NotchGeometryTests.external, config: config)
            let expected = geometry.contentFrame(height: NotchTab.defaultHeight - NotchTokens.padding, in: NotchGeometryTests.external.frame)
            #expect(try measuredToast(geometry) == expected, "\(config)")
        }
    }

    // MARK: the gap is part of the open pill for a click

    @Test func theGapAboveTheOpenPillIsFaintButNotTransparentSoAClickThereStaysInTheWindow() async throws {
        // Not the glass slab: the offscreen renderer draws a glass notch that takes drops as a flat placeholder, so a pixel there says
        // nothing (see `LiquidGlassTests`). The veil is one view outside the glass family, the same on every look, and the classic
        // look and the tiles show it.
        for look in Self.looks where look.2 == .tiles || look.0 == .classic {
            let host = try await HostedPill.make(.pill, look: look.0, clarity: look.1, shape: look.2, tabs: 2)
            defer { host.close() }
            let centre = host.hosting.bounds.midX
            let inGap = try host.alpha(at: CGPoint(x: centre, y: gap / 2))
            #expect(inGap > 0, "\(look): the veil is there")
            #expect(inGap < 0.05, "\(look): and too faint to see (\(inGap))")
            // The same row beside the open pill is the transparent panel, so a test can tell.
            #expect(try host.alpha(at: CGPoint(x: centre + 330, y: gap / 2)) == 0, "\(look)")
        }
    }

    @Test func theCollapsedPillHasNoVeilInItsGapAndTheNotchStyleHasNone() async throws {
        let collapsed = try await HostedPill.make(.pill, opened: false)
        defer { collapsed.close() }
        let centre = collapsed.hosting.bounds.midX
        #expect(try collapsed.alpha(at: CGPoint(x: centre, y: gap / 2)) == 0, "the gap above the collapsed pill is transparent")
        #expect(try collapsed.alpha(at: CGPoint(x: centre, y: gap + 12)) > 0.99, "and the pill is black")
        #expect(try collapsed.alpha(at: CGPoint(x: centre + 100, y: gap + 12)) == 0, "185 pt wide")
    }

    // MARK: switching while it is open

    @Test func changingTheStyleWhileOpenMovesTheNotchByTheGapAndBackWithoutRebuildingTheTab() async throws {
        for look in Self.looks {
            let host = try await HostedPill.make(.notch, look: look.0, clarity: look.1, shape: look.2, tabs: 2)
            defer { host.close() }
            let notch = try #require(host.probe.frame)

            host.show(.pill)
            // Where the pill puts the tab: the gap lower, and with tiles and a capsule where the pill's height puts the tile.
            let expected = expectedTabTop(HostedPill.screenGeometry(.pill), look, tabs: 2)
            try await host.wait("the pill") { host.probe.frame.map { abs($0.minY - expected) < 0.5 } ?? false }
            try await host.settle()
            let pill = try #require(host.probe.frame)
            #expect(abs(pill.minY - expected) < 0.01 && abs(pill.width - notch.width - 16) < 0.01, "\(look): \(notch) -> \(pill)")

            host.show(.notch)
            try await host.wait("the notch again") { host.probe.frame == notch }
            #expect(host.probe.frame == notch, "\(look): and back")
        }
    }

    @Test func aStyleChangeOnTheCollapsedAndAnActivePillDoesNotCrashAndEveryStateStillLaysOut() async throws {
        for style in VirtualNotchStyle.allCases {
            let host = try await HostedPill.make(style, look: .liquidGlass, shape: .tiles, tabs: 2, opened: false)
            defer { host.close() }
            host.model.showToast(AnyView(Color.clear), duration: .seconds(60))
            try await host.wait("the toast") { host.model.displayState == .toast }
            host.show(style == .pill ? .notch : .pill)
            host.model.open(tab: "probe")
            try await host.wait("the open notch") { host.model.displayState == .open("probe") && host.probe.frame != nil }
            host.model.close()
            try await host.wait("closed") { host.model.displayState == .closed }
            host.show(style)
            try await host.wait("laid out") { true }
        }
    }

    // MARK: where the open notch starts

    /// Where the open tab's top is for `geometry`, with `tabs` tabs, on each look: under the top inset (and the gap), then the tab bar or the
    /// tiles' capsule and padding when there are several.
    func expectedTabTop(_ geometry: NotchGeometry, _ look: (NotchLook, NotchGlassClarity, NotchGlassShape), tabs: Int) -> CGFloat {
        let top = geometry.topGap + geometry.openTopInset
        let tiled = look.0 == .liquidGlass && look.2 == .tiles
        switch (tiled, tabs >= 2) {
        case (false, false): return top
        case (false, true): return top + TabBarMetrics.iconSize.height + 6
        case (true, false): return top + NotchGlassPlan.tilePadding
        case (true, true):
            // Under the capsule and its gap: a notch's capsule is under the top inset, a pill's is the pill, at the top.
            let bar = geometry.tabBarCapsule(tabCount: tabs)!
            return geometry.topGap + bar.top + bar.height + NotchGlassPlan.tileGap + NotchGlassPlan.tilePadding
        }
    }

    @Test func theOpenTabStartsThePaddingBelowTheTopOnADisplayWithoutACutoutInBothStyles() async throws {
        for style in VirtualNotchStyle.allCases {
            for look in Self.looks {
                for tabs in [1, 2] {
                    let geometry = HostedPill.screenGeometry(style)
                    let (frame, _) = try await tab(style, look, tabs: tabs)
                    let expected = expectedTabTop(geometry, look, tabs: tabs)
                    #expect(abs(frame.minY - expected) < 0.01, "\(style) \(look) \(tabs) tabs: \(frame.minY), expected \(expected)")
                    // The notch's own 25 pt of body are not kept free any more.
                    #expect(frame.minY < geometry.topGap + geometry.notchSize.height + (tabs >= 2 ? 40 : 10), "\(style) \(look)")
                }
            }
        }
    }

    @Test func aMacBookStillKeepsTheCutoutFreeAndTheStyleSettingDoesNotReachIt() async throws {
        let macBook = NotchGeometryTests.macBook14
        for style in VirtualNotchStyle.allCases {
            for look in Self.looks {
                let host = try await HostedPill.make(style, on: macBook, look: look.0, clarity: look.1, shape: look.2, tabs: 2)
                defer { host.close() }
                let geometry = HostedPill.screenGeometry(style, on: macBook)
                let frame = try #require(host.probe.frame)
                #expect(geometry.openTopInset == 32 && geometry.topGap == 0)
                #expect(abs(frame.minY - expectedTabTop(geometry, look, tabs: 2)) < 0.01, "\(style) \(look): \(frame)")
                #expect(abs(frame.minY - (32 + (look.0 == .liquidGlass && look.2 == .tiles ? 30 + 8 + 8 : 24 + 6))) < 0.01)
            }
        }
    }

    @Test func theTabIsTheSizeItAskedForOnEveryDisplayAndOnlyTheBandAboveItDiffers() async throws {
        for look in Self.looks {
            let macBook = try await HostedPill.make(.notch, on: NotchGeometryTests.macBook14, look: look.0, clarity: look.1, shape: look.2, tabs: 2)
            defer { macBook.close() }
            let external = try await HostedPill.make(.notch, look: look.0, clarity: look.1, shape: look.2, tabs: 2)
            defer { external.close() }
            let (a, b) = (try #require(macBook.probe.frame), try #require(external.probe.frame))
            #expect(abs(a.height - b.height) < 0.01 && abs(a.width - b.width) < 0.01, "\(look): the same size \(a) \(b)")
            #expect(abs((a.minY - b.minY) - (32 - 14)) < 0.01, "\(look): 18 pt higher where there is no cutout")
        }
    }

    @Test func movingTheNotchBetweenADisplayWithACutoutAndOneWithoutMovesOnlyTheBandAndNothingRebuilds() async throws {
        for look in Self.looks {
            let host = try await HostedPill.make(.notch, on: NotchGeometryTests.macBook14, look: look.0, clarity: look.1, shape: look.2, tabs: 2)
            defer { host.close() }
            let built = try #require(host.probe.frame)
            let appeared = host.probe.appeared
            for style in [VirtualNotchStyle.notch, .pill] {
                host.show(style, on: NotchGeometryTests.external)
                try await host.wait("the display without a cutout") { host.probe.frame.map { abs($0.minY - built.minY) > 1 } ?? false }
                try await host.settle()
                let frame = try #require(host.probe.frame)
                let geometry = HostedPill.screenGeometry(style)
                #expect(abs(frame.minY - expectedTabTop(geometry, look, tabs: 2)) < 0.01, "\(look) \(style): \(frame)")
                #expect(abs(frame.height - built.height) < 0.01, "\(look) \(style): the tab keeps its height")
                host.show(.notch, on: NotchGeometryTests.macBook14)
                try await host.wait("the MacBook again") { host.probe.frame == built }
            }
            #expect(host.probe.appeared == appeared, "\(look): the tab was not rebuilt on the way (\(host.probe.appeared) against \(appeared))")
        }
    }

    // MARK: a tab has the same room in tiles as in one piece

    @Test func aTabHasExactlyTheRoomInTilesThatItHasInOnePieceOnEveryDisplayHeightAndNumberOfTabs() async throws {
        let displays: [(ScreenDescriptor, VirtualNotchStyle)] = [
            (NotchGeometryTests.macBook14, .notch), (NotchGeometryTests.external, .notch), (NotchGeometryTests.external, .pill),
        ]
        for (screen, style) in displays {
            for height in [CGFloat(120), 190, 240] {
                for tabs in [1, 2] {
                    let slab = try await HostedPill.make(style, on: screen, look: .liquidGlass, shape: .slab, tabs: tabs, height: height)
                    defer { slab.close() }
                    let reference = try #require(slab.probe.frame)
                    for (look, clarity) in [(NotchLook.liquidGlass, NotchGlassClarity.balanced), (.liquidGlass, .clear)] where height == 190 || clarity == .balanced {
                        let tiled = try await HostedPill.make(style, on: screen, look: look, clarity: clarity, shape: .tiles, tabs: tabs, height: height)
                        defer { tiled.close() }
                        let frame = try #require(tiled.probe.frame)
                        let name = "\(screen.safeAreaTop > 0 ? "MacBook" : "external \(style)") asks \(height), \(tabs) tabs, \(clarity)"
                        #expect(abs(frame.width - reference.width) < 0.01, "\(name): width \(frame.width) against \(reference.width)")
                        #expect(abs(frame.height - reference.height) < 0.01, "\(name): height \(frame.height) against \(reference.height)")
                        #expect(abs(frame.minX - reference.minX) < 0.01, "\(name): x")
                    }
                }
            }
        }
    }

    @Test func theTilesNotchIsTallerByTheChromeAndTheSlabAndTheClassicNotchAreAsTheyWere() async throws {
        let slab = try await HostedPill.make(.notch, on: NotchGeometryTests.macBook14, look: .liquidGlass, shape: .slab, tabs: 2)
        defer { slab.close() }
        let classic = try await HostedPill.make(.notch, on: NotchGeometryTests.macBook14, look: .classic, shape: .tiles, tabs: 2)
        defer { classic.close() }
        // The classic look has no tiles, whatever shape is stored: no chrome and the same frame as the slab's.
        #expect(try #require(classic.probe.frame).size == (try #require(slab.probe.frame)).size)
        #expect(!classic.tiles && !slab.tiles)
        let tiled = try await HostedPill.make(.notch, on: NotchGeometryTests.macBook14, look: .liquidGlass, shape: .tiles, tabs: 2)
        defer { tiled.close() }
        #expect(tiled.tiles)
        let geometry = HostedPill.screenGeometry(.notch, on: NotchGeometryTests.macBook14, tiles: true)
        #expect(geometry.shapeSize(for: .open("probe"), contentHeight: 190, tabCount: 2).height == CGFloat(32 + 190 + 24))
    }

    @Test func aToastIsTallerByTheChromeToo() async throws {
        // The toast covers the tab in the notch's own size, which with tiles includes their chrome: the root view and the window controller
        // hand the geometry the tab count for it.
        for tabs in [1, 2] {
            var heights: [Bool: CGFloat] = [:]
            for tiled in [false, true] {
                let host = try await HostedPill.make(.notch, on: NotchGeometryTests.macBook14, look: .liquidGlass, shape: tiled ? .tiles : .slab, tabs: tabs)
                defer { host.close() }
                let probe = host.probe
                host.model.showToast(
                    AnyView(Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.toast = $0 }), duration: .seconds(60)
                )
                try await host.wait("the toast") { host.model.displayState == .toast && probe.toast != nil }
                try await host.settle()
                heights[tiled] = try #require(probe.toast).height
            }
            let expected = NotchTilesLayout.extraHeight(tabCount: tabs)
            #expect(abs((heights[true] ?? 0) - (heights[false] ?? 0) - expected) < 0.01, "\(tabs) tabs: \(heights)")
        }
    }

    // MARK: the pill opens into the tab bar

    @Test func withTilesThePillsTabBarIsWhereThePillWasAndTheTileIsUnderItWithTheRoomOfOnePiece() async throws {
        for height in [CGFloat(24), 32, 40, 56] {
            for tabs in [2, 5] {
                let slab = try await HostedPill.make(.pill, look: .liquidGlass, shape: .slab, tabs: tabs, pillHeight: height)
                defer { slab.close() }
                let tiled = try await HostedPill.make(.pill, look: .liquidGlass, shape: .tiles, tabs: tabs, pillHeight: height)
                defer { tiled.close() }
                let (a, b) = (try #require(slab.probe.frame), try #require(tiled.probe.frame))
                let name = "pill \(height), \(tabs) tabs"
                // The tile starts under the pill (its height) and a gap, and the tile's padding.
                #expect(abs(b.minY - (NotchGeometry.pillTopGap + height + NotchGlassPlan.tileGap + NotchGlassPlan.tilePadding)) < 0.01, "\(name): \(b)")
                #expect(abs(b.width - a.width) < 0.01 && abs(b.height - a.height) < 0.01 && abs(b.minX - a.minX) < 0.01, "\(name): the room of one piece")
            }
        }
    }
}
