import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import WindowLayoutModule

/// A 14" MacBook (hardware notch, 982 pt tall, menu bar 37 pt) and an external display to its right, each with a notch.
@MainActor
final class SessionFixture {
    static let macBook = ScreenDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
        auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 665, menuBarHeight: 37
    )
    static let external = ScreenDescriptor(
        frame: CGRect(x: 1512, y: -98, width: 2560, height: 1440), safeAreaTop: 0,
        auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 25
    )
    static let macBookVisible = CGRect(x: 0, y: 0, width: 1512, height: 945)
    /// The external display's menu bar (25 pt) and a Dock of 80 pt at the bottom taken out.
    static let externalVisible = CGRect(x: 1512, y: -18, width: 2560, height: 1335)

    /// Where the pointer is near the MacBook's notch (it spans x 656 to 853, the bottom is y 950) without being over a tile:
    /// beside the notch, above the row of tiles, which starts under the notch.
    static let nearMacBook = CGPoint(x: 640, y: 975)
    static let macBookContent = NotchGeometry(screen: macBook, config: NotchLayoutConfig())
        .contentFrame(height: SnapTiles.height, in: macBook.frame)

    let window = FakeWindow(frame: CGRect(x: 600, y: 300, width: 800, height: 600))
    let probe: FakeWindowProbe
    let events = FakeDragEvents()
    let preview = FakePreview()
    let scheduler = ManualScheduler()
    var notches = [NotchDisplay(id: 1, screenFrame: macBook.frame, geometry: NotchGeometry(screen: macBook, config: NotchLayoutConfig()))]
    var screens = SnapScreens(screens: [SnapScreen(id: 1, visibleFrame: macBookVisible)], primaryHeight: 982)
    var options = SnapOptions(storedLayouts: [], gap: .none)
    var isTrusted = true
    private(set) var shown = 0
    private(set) var hidden = 0
    /// How many taps on the trackpad the session asked for.
    private(set) var felt = 0
    private(set) var session: SnapSession!
    private var time: TimeInterval = 0

    init() {
        probe = FakeWindowProbe(window)
        session = SnapSession(
            environment: SnapSession.Environment(
                isTrusted: { [unowned self] in isTrusted },
                notches: { [unowned self] in notches },
                screens: { [unowned self] in screens },
                options: { [unowned self] in options },
                showTiles: { [unowned self] _ in shown += 1 },
                hideTiles: { [unowned self] in hidden += 1 },
                feel: { [unowned self] in felt += 1 }
            ),
            probe: probe, events: events, makePreview: { [preview] in preview }, scheduler: scheduler
        )
    }

    var tiles: SnapTilesModel { session.tiles }

    /// Where tile `index` of a row of six is, in its middle.
    func tilePoint(_ index: Int, count: Int = 6) -> CGPoint {
        let frame = SnapTiles.frames(count: count, in: Self.macBookContent)[index]
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    func press() {
        session.handle(.down)
    }

    /// A mouse drag step: the window follows the pointer, as it does when it is dragged by its title bar.
    func drag(to point: CGPoint, movingWindow: Bool = true) {
        if movingWindow { window.drag(to: CGPoint(x: point.x - 200, y: 982 - point.y - 10)) }
        time += 0.05
        session.handle(.dragged(point, time: time))
    }

    /// Presses and drags a window until the drag is recognised, far from every notch.
    func startWindowDrag() {
        press()
        drag(to: CGPoint(x: 400, y: 500))
        drag(to: CGPoint(x: 420, y: 500))
        drag(to: CGPoint(x: 440, y: 500))
    }

    /// A window drag whose pointer is then brought to the notch, as a person does: the tiles are open.
    func openTiles() {
        startWindowDrag()
        drag(to: Self.nearMacBook)
    }

    func release(at point: CGPoint) {
        session.handle(.up(point))
    }

    func settle() {
        scheduler.advance(by: SnapSession.settleDelay + .milliseconds(10))
    }
}

@Suite struct SnapSessionTests {
    let fixture = SessionFixture()
    var far: CGPoint { CGPoint(x: 400, y: 500) }

    // MARK: when the tiles appear

    @Test func aDragThatMovesNoWindowNeverShowsTiles() {
        fixture.press()
        for step in 0..<12 { fixture.drag(to: CGPoint(x: 700 + CGFloat(step), y: 930), movingWindow: false) }
        #expect(fixture.shown == 0)
        #expect(!fixture.events.watchingEscape)
    }

    @Test func aWindowDraggedFarFromTheNotchShowsNothing() {
        fixture.startWindowDrag()
        fixture.drag(to: CGPoint(x: 900, y: 600))
        #expect(fixture.shown == 0)
        #expect(fixture.events.watchingEscape, "a window drag is on, so Escape is watched")
    }

    @Test func theTilesOpenOnceWhenTheWindowComesWithinFortyPointsOfTheNotch() {
        fixture.startWindowDrag()
        fixture.drag(to: SessionFixture.nearMacBook)
        #expect(fixture.shown == 1)
        fixture.drag(to: CGPoint(x: 645, y: 970))
        fixture.drag(to: CGPoint(x: 650, y: 965))
        #expect(fixture.shown == 1)
        #expect(fixture.tiles.layouts == SnapLayout.allCases)
        #expect(fixture.tiles.hovered == nil)
    }

    @Test func fortyPointsMeansFortyPointsFromTheNotchBodyOnEverySide() {
        // The notch's shape spans x 656...853 and the screen's top edge down to y 950.
        let outside = [CGPoint(x: 615, y: 960), CGPoint(x: 894, y: 960), CGPoint(x: 750, y: 909), CGPoint(x: 100, y: 975)]
        let inside = [CGPoint(x: 617, y: 960), CGPoint(x: 892, y: 960), CGPoint(x: 750, y: 911), CGPoint(x: 750, y: 982)]
        for point in outside {
            let fixture = SessionFixture()
            fixture.startWindowDrag()
            fixture.drag(to: point)
            #expect(fixture.shown == 0, "\(point) is more than 40 pt away")
        }
        for point in inside {
            let fixture = SessionFixture()
            fixture.startWindowDrag()
            fixture.drag(to: point)
            #expect(fixture.shown == 1, "\(point) is within 40 pt")
        }
    }

    @Test func aDisplayWithNoNotchIsLeftAlone() {
        fixture.notches = []
        fixture.startWindowDrag()
        fixture.drag(to: SessionFixture.nearMacBook)
        #expect(fixture.shown == 0)
    }

    @Test func withoutAccessibilityNoDragIsEverAWindowDrag() {
        fixture.isTrusted = false
        fixture.startWindowDrag()
        fixture.drag(to: SessionFixture.nearMacBook)
        #expect(fixture.shown == 0)
        #expect(fixture.probe.asked == 0)
    }

    // MARK: hovering

    @Test func hoveringATileSelectsItAndPreviewsWhereTheWindowWouldGo() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        #expect(fixture.tiles.hovered == SnapTarget(layout: .leftHalf, zone: 0))
        #expect(fixture.preview.frame == CGRect(x: 0, y: 0, width: 756, height: 945))
        fixture.drag(to: fixture.tilePoint(1))
        #expect(fixture.tiles.hovered == SnapTarget(layout: .rightHalf, zone: 0))
        #expect(fixture.preview.frame == CGRect(x: 756, y: 0, width: 756, height: 945))
    }

    @Test func aTileOfSeveralZonesPreviewsTheZoneUnderThePointer() {
        fixture.openTiles()
        let tile = SnapTiles.frames(count: 6, in: SessionFixture.macBookContent)[3]
        let glyph = SnapTiles.glyphFrame(in: tile)
        fixture.drag(to: CGPoint(x: glyph.minX + glyph.width * 0.75, y: glyph.maxY - glyph.height * 0.75))
        #expect(fixture.tiles.hovered == SnapTarget(layout: .quarters, zone: 3))
        #expect(fixture.preview.frame == CGRect(x: 756, y: 0, width: 756, height: 473))
    }

    @Test func betweenTilesThereIsNothingToPreview() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        let between = CGPoint(x: SnapTiles.frames(count: 6, in: SessionFixture.macBookContent)[0].maxX + 4, y: fixture.tilePoint(0).y)
        fixture.drag(to: fixture.tilePoint(0))
        fixture.drag(to: between)
        #expect(fixture.tiles.hovered == nil)
        #expect(!fixture.preview.isVisible)
        #expect(fixture.hidden == 0, "the tiles stay while the pointer is still over the notch")
    }

    @Test func theGapAndTheLayoutsComeFromTheCurrentOptions() {
        fixture.options = SnapOptions(storedLayouts: ["rightHalf", "thirds"], gap: .small)
        fixture.openTiles()
        #expect(fixture.tiles.layouts == [.rightHalf, .thirds])
        fixture.drag(to: fixture.tilePoint(0, count: 2))
        #expect(fixture.tiles.hovered == SnapTarget(layout: .rightHalf, zone: 0))
        #expect(fixture.preview.frame == CGRect(x: 760, y: 8, width: 744, height: 929))
    }

    // MARK: letting go

    @Test func releasingOverATileMovesTheWindowThere() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.release(at: fixture.tilePoint(0))
        // At once the tiles and the preview go.
        #expect(fixture.hidden == 1)
        #expect(!fixture.preview.isVisible)
        #expect(!fixture.events.watchingEscape)
        // The window is moved a moment later, after its own app has finished the drag it is still tracking.
        #expect(fixture.window.setFrames.isEmpty)
        fixture.settle()
        // The left half below the menu bar in Accessibility coordinates: y counts from the top of the primary display.
        #expect(fixture.window.setFrames == [CGRect(x: 0, y: 37, width: 756, height: 945)])
    }

    @Test func theWindowIsToldWhereTheZoneIsWhereTheDisplayIsVisibleAndWhichEdgeItIsAnchoredTo() {
        fixture.openTiles()
        let tile = SnapTiles.frames(count: 6, in: SessionFixture.macBookContent)[4]
        let glyph = SnapTiles.glyphFrame(in: tile)
        let rightThird = CGPoint(x: glyph.minX + glyph.width * 0.9, y: glyph.midY)
        fixture.drag(to: rightThird)
        fixture.release(at: rightThird)
        fixture.settle()
        let placement = fixture.window.placements.first
        // In Accessibility coordinates: below the 37 pt menu bar of the 982 pt display, y counted from the top.
        #expect(placement?.frame == CGRect(x: 1008, y: 37, width: 504, height: 945))
        #expect(placement?.area == CGRect(x: 0, y: 37, width: 1512, height: 945))
        #expect(placement?.anchor == SnapAnchor(horizontal: .trailing, vertical: .top))
    }

    @Test func theReleasePointDecidesNotTheLastDragPoint() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.release(at: fixture.tilePoint(2))
        fixture.settle()
        #expect(fixture.window.setFrames == [CGRect(x: 0, y: 37, width: 1512, height: 945)])
    }

    @Test func releasingOnAGapOrElsewhereMovesNothing() {
        let inGap = CGPoint(x: SnapTiles.frames(count: 6, in: SessionFixture.macBookContent)[1].maxX + 4, y: fixture.tilePoint(1).y)
        for point in [inGap, SessionFixture.nearMacBook, CGPoint(x: 900, y: 500), CGPoint(x: 5, y: 5)] {
            let fixture = SessionFixture()
            fixture.openTiles()
            fixture.drag(to: fixture.tilePoint(1))
            fixture.release(at: point)
            fixture.settle()
            #expect(fixture.window.setFrames.isEmpty, "released at \(point)")
            #expect(fixture.hidden == 1, "the tiles go whatever the release")
        }
    }

    @Test func leavingTheOpenNotchClosesTheTilesAndALaterReleaseMovesNothing() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.drag(to: CGPoint(x: 300, y: 400))
        #expect(fixture.hidden == 1)
        #expect(!fixture.preview.isVisible)
        fixture.release(at: fixture.tilePoint(0))
        fixture.settle()
        #expect(fixture.window.setFrames.isEmpty, "a release over a tile counts only while the tiles are open")
        #expect(fixture.hidden == 1, "no second close")
    }

    @Test func theTilesStayOpenWhileThePointerCrossesTheNotchOnItsWayDown() {
        fixture.openTiles()
        // Down to just below the row: outside the 40 pt around the notch, inside the open notch.
        fixture.drag(to: CGPoint(x: 760, y: SessionFixture.macBookContent.minY - 10))
        #expect(fixture.hidden == 0)
        fixture.drag(to: CGPoint(x: 760, y: SessionFixture.macBookContent.minY - 40))
        #expect(fixture.hidden == 1)
    }

    @Test func aRefusedMoveIsTriedOnceAndForgotten() {
        fixture.window.accepts = false
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.release(at: fixture.tilePoint(0))
        fixture.settle()
        #expect(fixture.window.setFrames.count == 1)
    }

    // MARK: the tap on the trackpad

    @Test func aWindowThatSnappedIntoATileIsFeltOnceAndOnlyWhenItHasMoved() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        #expect(fixture.felt == 0, "hovering a tile is not a snap")
        fixture.release(at: fixture.tilePoint(0))
        #expect(fixture.felt == 0, "the window has not moved yet")
        fixture.settle()
        #expect(fixture.window.setFrames.count == 1)
        #expect(fixture.felt == 1)
        fixture.settle()
        #expect(fixture.felt == 1, "once for the one snap")
    }

    @Test func aWindowTheAppRefusedToMoveIsNotFelt() {
        fixture.window.accepts = false
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.release(at: fixture.tilePoint(0))
        fixture.settle()
        #expect(fixture.window.setFrames.count == 1)
        #expect(fixture.felt == 0, "nothing snapped")
    }

    @Test func aDropThatMovesNothingFeelsNothing() {
        let inGap = CGPoint(x: SnapTiles.frames(count: 6, in: SessionFixture.macBookContent)[1].maxX + 4, y: fixture.tilePoint(1).y)
        for point in [inGap, SessionFixture.nearMacBook, CGPoint(x: 900, y: 500)] {
            let fixture = SessionFixture()
            fixture.openTiles()
            fixture.drag(to: fixture.tilePoint(1))
            fixture.release(at: point)
            fixture.settle()
            #expect(fixture.felt == 0, "released at \(point)")
        }
    }

    @Test func aCancelledDragAndAStoppedModuleFeelNothing() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.session.handle(.escape)
        fixture.release(at: fixture.tilePoint(0))
        fixture.settle()
        #expect(fixture.felt == 0, "Escape cancelled it")

        let other = SessionFixture()
        other.openTiles()
        other.drag(to: other.tilePoint(0))
        other.release(at: other.tilePoint(0))
        other.session.stop()
        other.settle()
        #expect(other.felt == 0, "the move was cancelled with the module")
    }

    @Test func theWindowMovedIsTheOneThatWasDragged() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        // Another window takes the focus while the move waits.
        let other = FakeWindow()
        fixture.probe.focused = other
        fixture.release(at: fixture.tilePoint(0))
        fixture.settle()
        #expect(fixture.window.setFrames.count == 1)
        #expect(other.setFrames.isEmpty)
    }

    // MARK: Escape

    @Test func escapeClosesTheTilesAndTheReleaseThatFollowsMovesNothing() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.session.handle(.escape)
        #expect(fixture.hidden == 1)
        #expect(!fixture.preview.isVisible)
        // Back over a tile: nothing opens again until the next press.
        fixture.drag(to: SessionFixture.nearMacBook)
        fixture.drag(to: fixture.tilePoint(0))
        #expect(fixture.shown == 1)
        fixture.release(at: fixture.tilePoint(0))
        fixture.settle()
        #expect(fixture.window.setFrames.isEmpty)
        #expect(!fixture.events.watchingEscape)
    }

    @Test func escapeWithoutAWindowDragDoesNothing() {
        fixture.press()
        fixture.session.handle(.escape)
        fixture.drag(to: CGPoint(x: 400, y: 500))
        fixture.drag(to: CGPoint(x: 420, y: 500))
        fixture.drag(to: CGPoint(x: 440, y: 500))
        fixture.drag(to: SessionFixture.nearMacBook)
        #expect(fixture.shown == 1, "an Escape from before the window drag began does not cancel it")
    }

    @Test func theNextPressAfterEscapeWorksAgain() {
        fixture.openTiles()
        fixture.session.handle(.escape)
        fixture.release(at: SessionFixture.nearMacBook)
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(4))
        fixture.release(at: fixture.tilePoint(4))
        fixture.settle()
        #expect(fixture.window.setFrames.count == 1)
    }

    // MARK: displays

    @Test func movingToAnotherDisplaysNotchMovesTheTilesThere() {
        fixture.notches.append(NotchDisplay(
            id: 2, screenFrame: SessionFixture.external.frame, geometry: NotchGeometry(screen: SessionFixture.external, config: NotchLayoutConfig())
        ))
        fixture.screens = SnapScreens(
            screens: [
                SnapScreen(id: 1, visibleFrame: SessionFixture.macBookVisible),
                SnapScreen(id: 2, visibleFrame: SessionFixture.externalVisible),
            ],
            primaryHeight: 982
        )
        fixture.openTiles()
        #expect(fixture.shown == 1)
        // Straight to the notch of the display on the right (centred at x 2792, its top edge at y 1342).
        fixture.drag(to: CGPoint(x: 2792, y: 1320))
        #expect(fixture.hidden == 1 && fixture.shown == 2)
        let content = NotchGeometry(screen: SessionFixture.external, config: NotchLayoutConfig())
            .contentFrame(height: SnapTiles.height, in: SessionFixture.external.frame)
        let tile = SnapTiles.frames(count: 6, in: content)[2]
        let point = CGPoint(x: tile.midX, y: tile.midY)
        fixture.drag(to: point)
        #expect(fixture.preview.frame == SessionFixture.externalVisible)
        fixture.release(at: point)
        fixture.settle()
        // Full screen of the external display: below its menu bar, whose top is at 1342 - 25 = 1317, so 982 - 1317 = -335
        // in Accessibility coordinates.
        #expect(fixture.window.setFrames == [CGRect(x: 1512, y: -335, width: 2560, height: 1335)])
    }

    // MARK: lifecycle

    @Test func stoppingDuringADragClosesTheTilesAndNeverMovesTheWindow() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.session.stop()
        #expect(fixture.hidden == 1)
        #expect(!fixture.preview.isVisible)
        #expect(!fixture.events.watchingEscape)
        fixture.release(at: fixture.tilePoint(0))
        fixture.settle()
        #expect(fixture.window.setFrames.isEmpty)
    }

    @Test func stoppingWhileAMoveWaitsCancelsTheMove() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.release(at: fixture.tilePoint(0))
        fixture.session.stop()
        fixture.settle()
        #expect(fixture.window.setFrames.isEmpty)
    }

    @Test func stoppingWithNothingOpenClosesNothing() {
        fixture.session.stop()
        #expect(fixture.hidden == 0)
    }

    @Test func eachDragStartsFromScratch() {
        fixture.openTiles()
        fixture.drag(to: fixture.tilePoint(0))
        fixture.release(at: fixture.tilePoint(0))
        #expect(fixture.tiles.hovered == nil)
        fixture.openTiles()
        #expect(fixture.shown == 2)
        #expect(fixture.tiles.hovered == nil)
    }

    @Test func thePreviewIsOnlyBuiltOnceItIsNeeded() {
        var built = 0
        let session = SnapSession(
            environment: SnapSession.Environment(
                isTrusted: { true }, notches: { [] }, screens: { fixture.screens }, options: { fixture.options },
                showTiles: { _ in }, hideTiles: {}, feel: {}
            ),
            probe: fixture.probe, events: fixture.events, makePreview: { built += 1; return fixture.preview }, scheduler: fixture.scheduler
        )
        session.handle(.down)
        session.handle(.dragged(far, time: 1))
        session.stop()
        #expect(built == 0)
    }
}
