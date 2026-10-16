import AppKit
import CoreGraphics
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

private final class TopModule: FeatureModule {
    let descriptor: ModuleDescriptor
    init(_ id: ModuleID, order: Int) {
        descriptor = ModuleDescriptor(id: id, displayName: id.rawValue, systemImage: "circle", defaultEnabled: true, order: order)
    }
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: descriptor.displayName, systemImage: "circle", preferredHeight: 190, content: AnyView(EmptyView()))
    }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

/// A screen with no cutout for the camera keeps no band of its open notch free for it: the tab page starts near the top, under the pill's
/// gap for the pill, and a screen with a hardware notch is what it was.
@Suite struct NotchOpenFromTheTopTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let notch = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())
    let pill = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))
    let padding = NotchTokens.padding

    // MARK: the inset

    @Test func aHardwareNotchKeepsItsCutoutFreeAndEveryOtherScreenTheConcentricPadding() {
        #expect(macBook.openTopInset == macBook.notchSize.height)
        #expect(macBook.openTopInset == 32)
        #expect(notch.openTopInset == padding)
        #expect(pill.openTopInset == padding)
        // Whatever the size of the virtual notch, which only sizes the collapsed one.
        for config in [
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40), NotchLayoutConfig(virtualNotchWidth: 120, virtualNotchHeight: 24),
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, virtualNotchStyle: .pill),
        ] {
            #expect(NotchGeometry(screen: NotchGeometryTests.external, config: config).openTopInset == padding)
        }
        // And the style setting does not reach a hardware notch.
        #expect(NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(virtualNotchStyle: .pill)).openTopInset == 32)
    }

    @Test func theOpenShapeIsTheContentAndTheInsetTallInEveryStyle() {
        for content in stride(from: NotchTab.heightRange.lowerBound, through: NotchGeometry.maxContentHeight, by: 10) {
            for state in [NotchState.open("a"), .open(nil), .toast] {
                #expect(macBook.shapeSize(for: state, contentHeight: content).height == 32 + content, "hardware, as today")
                #expect(notch.shapeSize(for: state, contentHeight: content).height == 14 + content, "notch style, no cutout")
                #expect(pill.shapeSize(for: state, contentHeight: content).height == 14 + content, "pill, no cutout")
            }
        }
        // The widths are untouched.
        #expect(notch.shapeSize(for: .open(nil)).width == macBook.shapeSize(for: .open(nil)).width)
    }

    @Test func theCollapsedNotchItsStripBubblesAndListOfADisplayWithoutACutoutAreAsTheyWereAndAToastIsTheOpenShape() {
        #expect(notch.shapeSize(for: .closed) == CGSize(width: 185 + 12, height: 25))
        #expect(notch.shapeSize(for: .compact, bottomHeight: 30) == CGSize(width: 185 + 12 + 128, height: 55))
        #expect(notch.bubbleFrame(at: 0) == CGRect(x: 162.5, y: 0, width: 25, height: 25))
        #expect(notch.listHeight(rows: 3) == 96)
        #expect(notch.bottomHeight(for: .compact, strip: 30, listRows: 0) == 30)
        // A toast is the open notch's size on both.
        #expect(notch.shapeSize(for: .toast, contentHeight: 130) == notch.shapeSize(for: .open(nil), contentHeight: 130))
        #expect(pill.shapeSize(for: .toast, contentHeight: 130) == pill.shapeSize(for: .open(nil), contentHeight: 130))
    }

    // MARK: where it is

    @Test func theContentStartsAtTheTopInsetUnderTheEdgeOrUnderThePillsGap() {
        let frame = NotchGeometryTests.external.frame
        let onNotch = notch.contentFrame(height: 100, in: frame)
        let onPill = pill.contentFrame(height: 100, in: frame)
        #expect(frame.maxY - onNotch.maxY == padding, "right under the top edge, the padding in")
        #expect(frame.maxY - onPill.maxY == NotchGeometry.pillTopGap + padding, "under the gap, the padding in")
        #expect(onNotch.height == onPill.height && onPill.width - onNotch.width == 16, "the pill has no ears")
        // A MacBook's is where it was.
        let book = NotchGeometryTests.macBook14.frame
        #expect(book.maxY - macBook.contentFrame(height: 100, in: book).maxY == 32)
    }

    @Test func theHitAreaOfTheOpenNotchIsSmallerByTheBandThatIsGone() {
        let frame = NotchGeometryTests.external.frame
        let band: CGFloat = 25 - padding
        let oldHeight: CGFloat = 25 + 190 + 8 + 1
        let onNotch = notch.hitRect(for: .open(nil), contentHeight: 190, in: frame)
        #expect(onNotch.height == oldHeight - band, "the hover and close area follow the shape")
        #expect(onNotch.minY == frame.maxY - (14 + 190) - 8)
        let onPill = pill.hitRect(for: .open(nil), contentHeight: 190, in: frame)
        #expect(onPill.height == oldHeight - band + NotchGeometry.pillTopGap, "the same, and the gap above it")
        #expect(onPill.minY == frame.maxY - NotchGeometry.pillTopGap - (14 + 190) - 8)
        #expect(notch.dragHitRect(for: .open(nil), contentHeight: 190, in: frame).height == CGFloat(14 + 190 + 40 + 1))
        // Just under the old, taller shape is outside now.
        let under = CGPoint(x: frame.midX, y: frame.maxY - (25 + 190) - 4)
        #expect(notch.pointerZone(at: under, state: .open(nil), contentHeight: 190, in: frame) == .outside)
        #expect(macBook.pointerZone(at: CGPoint(x: 754.5, y: 982 - (32 + 190) - 4), state: .open(nil), contentHeight: 190, in: NotchGeometryTests.macBook14.frame) == .notch)
    }

    @Test func thePanelHoldsEveryShapeAndIsNotSmallerBecauseTheListUnderTheCollapsedNotchNeedsAllOfIt() {
        // The open notch is shorter by the band, but the list of up to eight rows under the collapsed notch is not, so the panel is the same.
        #expect(notch.panelSize == CGSize(width: 900, height: 25 + 240))
        let tallestList = notch.shapeSize(for: .compact, bottomHeight: notch.listHeight(rows: NotchGeometry.maxListRows))
        #expect(tallestList.height + 4 >= notch.panelSize.height - 8, "the list is what the panel is as tall as")
        for geometry in [notch, pill] {
            let panel = geometry.panelFrame(in: NotchGeometryTests.external.frame)
            for state in [NotchState.open(nil), .toast, .compact] {
                let size = geometry.shapeSize(for: state, contentHeight: 240, bottomHeight: geometry.listHeight(rows: NotchGeometry.maxListRows))
                let rect = CGRect(x: panel.midX - size.width / 2, y: panel.maxY - geometry.topGap - size.height, width: size.width, height: size.height)
                #expect(panel.contains(rect), "\(state)")
            }
        }
    }

    // MARK: the tiles

    func tiles(_ geometry: NotchGeometry, tabs: Int = 2, content: CGFloat = 190) -> (rest: NotchTilesLayout, open: NotchTilesLayout) {
        let collapsed = geometry.cornerRadii(for: .closed)
        return (
            NotchTilesLayout.rest(collapsedSize: geometry.shapeSize(for: .closed), topRadius: collapsed.top, hasTabBar: tabs >= 2),
            NotchTilesLayout.open(
                shapeSize: geometry.shapeSize(for: .open(nil), contentHeight: content), topInset: geometry.openTopInset,
                topRadius: geometry.cornerRadii(for: .open(nil)).top, tabCount: tabs
            )
        )
    }

    @Test func theTilesOfADisplayWithoutACutoutStartAsTheCollapsedNotchAndEndHigher() {
        for (name, geometry) in [("notch", notch), ("pill", pill)] {
            let (rest, open) = tiles(geometry)
            let book = tiles(macBook)
            // They start where they always did: the collapsed notch's body, at the top of the shape.
            #expect(rest.content.top == 0 && rest.tabBar?.top == 0, Comment(rawValue: name))
            #expect(rest.content.size.height == geometry.notchSize.height, Comment(rawValue: name))
            // And they end the padding below the top: the capsule first, then the tile, the same gaps as on a MacBook.
            #expect(open.tabBar?.top == padding, "\(name): the capsule is the padding under the top")
            #expect(open.content.top == padding + 30 + NotchGlassPlan.tileGap, Comment(rawValue: name))
            #expect(open.content.top == (book.open.content.top) - (32 - 14), "\(name): 18 pt higher than on a MacBook")
            #expect(open.tabBar?.size == book.open.tabBar?.size, "\(name): the capsule is the same")
            #expect(open.content.size.height == geometry.shapeSize(for: .open(nil), contentHeight: 190).height - padding - open.content.top, Comment(rawValue: name))
            #expect(open.content.size.height == book.open.content.size.height, "\(name): the tile is as tall as on a MacBook: the content asked for it")
        }
    }

    @Test func aSingleTabHasOnlyTheTileUnderTheTopInset() {
        for geometry in [notch, pill] {
            let (_, open) = tiles(geometry, tabs: 1)
            #expect(open.tabBar == nil)
            #expect(open.content.top == padding)
            #expect(open.content.size.height == 190 - padding)
        }
    }

    @Test func aMacBooksTilesAreUnchanged() {
        let (rest, open) = tiles(macBook)
        #expect(open.tabBar?.top == 32 && open.content.top == 32 + 30 + NotchGlassPlan.tileGap)
        #expect(rest.content.top == 0 && rest.content.size == CGSize(width: 185, height: 32))
    }

    // MARK: the concentric padding

    @Test func onAPillTheContentIsTheSameDistanceFromAllFourEdges() {
        let (_, open) = tiles(pill, tabs: 1)
        let size = pill.shapeSize(for: .open(nil), contentHeight: 190)
        #expect(open.content.top == padding)
        #expect(open.content.top + open.content.size.height + padding == size.height, "the padding below")
        #expect(open.content.size.width + 2 * padding == size.width, "and at the sides")
    }
}

/// The notch moving from one screen to another: each screen has its own controller, panel and geometry, so a display with a cutout and one
/// without share nothing but the modules, and what they ask for is the same on both.
@Suite struct NotchBetweenDisplaysTests {
    let harness = RegistryHarness([TopModule("a", order: 1), TopModule("b", order: 2)])

    func controller(on screen: ScreenDescriptor, _ style: VirtualNotchStyle = .notch) async -> NotchWindowController {
        await harness.registry.bootstrap()
        return NotchWindowController(
            displayID: 1, screen: screen, config: NotchLayoutConfig(virtualNotchStyle: style), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities,
            delays: { (.milliseconds(150), .milliseconds(300)) }, captureHiding: { .never }, swipesBetweenTabs: { true }
        )
    }

    @Test func theTabGetsTheSameContentHeightOnADisplayWithACutoutAndOneWithout() async {
        let builtIn = await controller(on: NotchGeometryTests.macBook14)
        defer { builtIn.close() }
        let external = await controller(on: NotchGeometryTests.external, .pill)
        defer { external.close() }
        for controller in [builtIn, external] { controller.model.open(tab: "a") }
        #expect(builtIn.model.displayState == .open("a") && external.model.displayState == .open("a"))
        let height = harness.registry.contentHeight(for: .open("a"), tabUnderToast: nil)
        for controller in [builtIn, external] {
            let geometry = controller.display.geometry
            let size = geometry.shapeSize(for: .open("a"), contentHeight: height)
            #expect(size.height - geometry.openTopInset == height, "the same content height whatever is above it")
        }
        // Closing one leaves the other open.
        external.model.close()
        #expect(builtIn.model.displayState == .open("a"))
    }

    @Test func aControllerThatTakesAnotherScreenWhileOpenKeepsTheNotchOpenAndTakesItsBand() async {
        let controller = await controller(on: NotchGeometryTests.macBook14)
        defer { controller.close() }
        controller.model.open(tab: "b")
        #expect(controller.geometry.openTopInset == 32)
        controller.update(displayID: 2, screen: NotchGeometryTests.external, config: NotchLayoutConfig(virtualNotchStyle: .pill))
        #expect(controller.geometry.kind == .virtual && controller.geometry.openTopInset == 14 && controller.geometry.isPill)
        #expect(controller.model.displayState == .open("b"), "nothing closed it")
        controller.update(displayID: 1, screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(virtualNotchStyle: .pill))
        #expect(controller.geometry.kind == .hardware && controller.geometry.openTopInset == 32 && !controller.geometry.isPill)
        #expect(controller.model.displayState == .open("b"))
    }
}
