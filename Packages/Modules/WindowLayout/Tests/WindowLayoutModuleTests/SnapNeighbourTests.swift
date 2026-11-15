import CoreGraphics
import Foundation
import Testing
@testable import WindowLayoutModule

/// Windows snapped one after the other, through the whole session (tiles, drop, settle delay), with fake windows that keep
/// a smallest size like real apps do. The MacBook's visible area is 1512 x 945 below the 37 pt menu bar; tiles are
/// `SnapLayout.allCases`: 0 left half, 1 right half, 2 top half, 3 bottom half, 4 full screen, 5 left 2/3, 6 right 2/3, 7 quarters, 8 thirds, 9 focus.
@Suite struct SnapNeighbourTests {
    let fixture = SessionFixture()
    let cleanMyMac = FakeWindow(app: SnapApp(bundleID: "com.macpaw.CleanMyMac", name: "CleanMyMac"), minimum: CGSize(width: 1040, height: 0))
    let music = FakeWindow(app: SnapApp(bundleID: "com.apple.Music", name: "Music"))

    static let leftTile = 0, rightTile = 1, topTile = 2, bottomTile = 3
    static let fullScreenTile = 4, leftTwoThirdsTile = 5, rightTwoThirdsTile = 6
    static let quartersTile = 7, thirdsTile = 8, focusTile = 9

    func window(_ bundleID: String, name: String? = nil, minimum: CGSize = .zero) -> FakeWindow {
        FakeWindow(app: SnapApp(bundleID: bundleID, name: name ?? bundleID), minimum: minimum)
    }

    func overlap(_ first: FakeWindow, _ second: FakeWindow) -> Bool {
        !(first.current ?? .null).intersection(second.current ?? .null).isEmpty
    }

    // MARK: the case from the screenshot

    @Test func aWindowThatCannotBeNarrowedLeavesTheRestOfTheScreenToTheNextOne() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        fixture.snap(music, tile: Self.rightTile)
        #expect(cleanMyMac.current == CGRect(x: 0, y: 37, width: 1040, height: 945))
        #expect(music.current == CGRect(x: 1040, y: 37, width: 472, height: 945))
        #expect(!overlap(cleanMyMac, music))
        #expect(music.setFrames == [CGRect(x: 1040, y: 37, width: 472, height: 945)], "asked for the free part at once")
        #expect(fixture.notices == ["CleanMyMac không thu nhỏ được tới ô này (tối thiểu 1040 pt)"])
    }

    @Test func theSameInTheOtherOrderCoversNothingButIsSaidOut() {
        fixture.snap(music, tile: Self.rightTile)
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        // The other window is not moved behind its back: the left half's own zone is free of it, the window is not.
        #expect(music.current == CGRect(x: 756, y: 37, width: 756, height: 945))
        #expect(music.placements.count == 1)
        #expect(cleanMyMac.current == CGRect(x: 0, y: 37, width: 1040, height: 945))
        #expect(overlap(cleanMyMac, music))
        #expect(fixture.notices == ["CleanMyMac không thu nhỏ được tới ô này (tối thiểu 1040 pt)"])
    }

    // MARK: the gap between windows that accept their zone

    @Test func twoHalvesMeetExactlyOrAWholeGapApartForEveryGapAndArea() {
        let areas = [
            SessionFixture.macBookVisible,
            CGRect(x: 3, y: 5, width: 1001, height: 701),
            CGRect(x: 0.5, y: 37.25, width: 1511.5, height: 944.5),
            CGRect(x: 60, y: 70, width: 1451, height: 875),
            // A Dock whose size is not a whole number of points leaves a visible area with fractional edges.
            CGRect(x: 0, y: 0, width: 1451.5, height: 944.5),
            CGRect(x: 60.5, y: 69.5, width: 1451.5, height: 875.5),
            CGRect(x: 0.4, y: 37.3, width: 1511.2, height: 944.6),
        ]
        for area in areas {
            for gap in SnapGap.allCases {
                for rightFirst in [false, true] {
                    let fixture = SessionFixture()
                    fixture.screens = SnapScreens(screens: [SnapScreen(id: 1, visibleFrame: area)], primaryHeight: 982)
                    fixture.options = SnapOptions(storedLayouts: [], gap: gap)
                    let left = window("com.example.left"), right = window("com.example.right")
                    if rightFirst {
                        fixture.snap(right, tile: Self.rightTile)
                        fixture.snap(left, tile: Self.leftTile)
                    } else {
                        fixture.snap(left, tile: Self.leftTile)
                        fixture.snap(right, tile: Self.rightTile)
                    }
                    let name = "\(area) gap \(gap.points) right first \(rightFirst)"
                    guard let first = left.current, let second = right.current else {
                        Issue.record("a window was lost: \(name)")
                        continue
                    }
                    #expect(second.minX - first.maxX == gap.points, "\(name)")
                    #expect(first.intersection(second).isEmpty, "\(name)")
                    #expect(first.minY == second.minY && first.height == second.height, "\(name)")
                    #expect(left.placements.count == 1 && right.placements.count == 1, "\(name): each window was asked once, for its own zone")
                    #expect(fixture.notices.isEmpty, "\(name)")
                }
            }
        }
    }

    @Test func halvesMeetAtTheMiddleOfTheScreenWithoutAGap() {
        let left = window("com.example.left"), right = window("com.example.right")
        fixture.snap(left, tile: Self.leftTile)
        fixture.snap(right, tile: Self.rightTile)
        #expect(left.current?.maxX == 756 && right.current?.minX == 756)
    }

    @Test func aWindowNextToANeighbourKeepsTheGapToIt() {
        for gap in [SnapGap.small, .large] {
            let fixture = SessionFixture()
            fixture.options = SnapOptions(storedLayouts: [], gap: gap)
            let wide = window("com.example.wide", minimum: CGSize(width: 1040, height: 0)), next = window("com.example.next")
            fixture.snap(wide, tile: Self.leftTile)
            fixture.snap(next, tile: Self.rightTile)
            guard let first = wide.current, let second = next.current else { return }
            #expect(first.width == 1040)
            #expect(second.minX - first.maxX == gap.points, "gap \(gap.points)")
            // The window against the screen's edge keeps its own gap there.
            #expect(second.maxX == 1512 - gap.points, "gap \(gap.points)")
        }
    }

    // MARK: thirds and quarters

    @Test func aThirdThatKeptAWiderSizeNarrowsTheNextOneAndLeavesTheThirdAfterItAlone() {
        let first = window("com.example.a", minimum: CGSize(width: 700, height: 0))
        let second = window("com.example.b"), third = window("com.example.c")
        fixture.snap(first, tile: Self.thirdsTile, zone: 0)
        fixture.snap(second, tile: Self.thirdsTile, zone: 1)
        fixture.snap(third, tile: Self.thirdsTile, zone: 2)
        #expect(first.current == CGRect(x: 0, y: 37, width: 700, height: 945))
        #expect(second.current == CGRect(x: 700, y: 37, width: 308, height: 945))
        #expect(third.current == CGRect(x: 1008, y: 37, width: 504, height: 945))
        #expect(!overlap(first, second) && !overlap(second, third) && !overlap(first, third))
        #expect(third.placements.count == 1, "nothing was in the way of the third one")
    }

    @Test func aNeighbourOverTwoThirdsNarrowsTheOneItReachesPartlyAndNotTheOneItCovers() {
        let first = window("com.example.a", minimum: CGSize(width: 1100, height: 0))
        let second = window("com.example.b"), third = window("com.example.c")
        fixture.snap(first, tile: Self.thirdsTile, zone: 0)
        fixture.snap(second, tile: Self.thirdsTile, zone: 1)
        fixture.snap(third, tile: Self.thirdsTile, zone: 2)
        // The middle third has no room at all, so it goes where the layout says, over the first window.
        #expect(second.current == CGRect(x: 504, y: 37, width: 504, height: 945))
        #expect(second.setFrames.count == 1, "no room: no attempt")
        #expect(third.current == CGRect(x: 1100, y: 37, width: 412, height: 945))
    }

    @Test func theMiddleThirdFitsBetweenTwoThirdsThatKeptWiderSizes() {
        let first = window("com.example.a", minimum: CGSize(width: 600, height: 0))
        let last = window("com.example.c", minimum: CGSize(width: 612, height: 0))
        let middle = window("com.example.b")
        fixture.snap(first, tile: Self.thirdsTile, zone: 0)
        fixture.snap(last, tile: Self.thirdsTile, zone: 2)
        fixture.snap(middle, tile: Self.thirdsTile, zone: 1)
        #expect(first.current == CGRect(x: 0, y: 37, width: 600, height: 945))
        #expect(last.current == CGRect(x: 900, y: 37, width: 612, height: 945))
        #expect(middle.current == CGRect(x: 600, y: 37, width: 300, height: 945))
    }

    @Test func aWideTopLeftQuarterNarrowsTheTopRightOneAndLeavesTheBottomOnesAlone() {
        let topLeft = window("com.example.tl", minimum: CGSize(width: 1000, height: 0))
        let topRight = window("com.example.tr"), bottomRight = window("com.example.br")
        fixture.snap(topLeft, tile: Self.quartersTile, zone: 0)
        fixture.snap(topRight, tile: Self.quartersTile, zone: 1)
        fixture.snap(bottomRight, tile: Self.quartersTile, zone: 3)
        #expect(topLeft.current == CGRect(x: 0, y: 37, width: 1000, height: 472))
        #expect(topRight.current == CGRect(x: 1000, y: 37, width: 512, height: 472))
        #expect(bottomRight.current == CGRect(x: 756, y: 509, width: 756, height: 473), "a diagonal neighbour is not in the way")
    }

    @Test func aTallBottomQuarterNarrowsTheHeightOfTheTopOneAboveIt() {
        let bottomLeft = window("com.example.bl", minimum: CGSize(width: 0, height: 700))
        let topLeft = window("com.example.tl")
        fixture.snap(bottomLeft, tile: Self.quartersTile, zone: 2)
        fixture.snap(topLeft, tile: Self.quartersTile, zone: 0)
        #expect(bottomLeft.current == CGRect(x: 0, y: 282, width: 756, height: 700))
        #expect(topLeft.current == CGRect(x: 0, y: 37, width: 756, height: 245))
        #expect(fixture.notices == ["com.example.bl không thu nhỏ được tới ô này (tối thiểu 700 pt chiều cao)"])
    }

    // MARK: neighbours that no longer count

    @Test func aNeighbourTheUserMovedAwayIsIgnored() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        cleanMyMac.drag(to: CGPoint(x: 300, y: 300))
        fixture.snap(music, tile: Self.rightTile)
        #expect(music.current == CGRect(x: 756, y: 37, width: 756, height: 945))
        #expect(music.placements.count == 1)
    }

    @Test func aNeighbourTheUserResizedIsIgnored() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        cleanMyMac.current = CGRect(x: 0, y: 37, width: 1200, height: 945)
        fixture.snap(music, tile: Self.rightTile)
        #expect(music.current == CGRect(x: 756, y: 37, width: 756, height: 945))
    }

    @Test func aNeighbourThatWasClosedIsIgnored() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        cleanMyMac.close()
        fixture.snap(music, tile: Self.rightTile)
        #expect(music.current == CGRect(x: 756, y: 37, width: 756, height: 945))
    }

    @Test func nothingIsRememberedOnceTheModuleStopped() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        fixture.session.stop()
        fixture.snap(music, tile: Self.rightTile)
        #expect(music.current == CGRect(x: 756, y: 37, width: 756, height: 945))
    }

    @Test func aWindowIsNeverItsOwnNeighbour() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        fixture.snap(cleanMyMac, tile: Self.rightTile)
        #expect(cleanMyMac.setFrames.last == CGRect(x: 756, y: 37, width: 756, height: 945), "asked for the whole right half")
        #expect(cleanMyMac.current == CGRect(x: 472, y: 37, width: 1040, height: 945))
    }

    @Test func windowsOfAnotherLayoutFamilyOrInTheSameZoneAreNotNeighbours() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        let third = window("com.example.third"), same = window("com.example.same")
        fixture.snap(third, tile: Self.thirdsTile, zone: 2)
        #expect(third.current == CGRect(x: 1008, y: 37, width: 504, height: 945), "halves and thirds are not one family")
        fixture.snap(same, tile: Self.leftTile)
        #expect(same.current == CGRect(x: 0, y: 37, width: 756, height: 945), "a window in the same zone is stacked on purpose")
    }

    @Test func windowsInFullScreenOrFocusHaveNoNeighbours() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        let focus = window("com.example.focus"), full = window("com.example.full")
        fixture.snap(focus, tile: Self.focusTile)
        fixture.snap(full, tile: Self.fullScreenTile)
        #expect(focus.current == CGRect(x: 252, y: 37, width: 1008, height: 945))
        #expect(full.current == CGRect(x: 0, y: 37, width: 1512, height: 945))
    }

    // MARK: when even the free part is too small

    @Test func aWindowThatCannotShrinkToTheFreePartStaysAtItsSmallestSizeAgainstTheOuterEdgeAndSaysSo() {
        let narrow = window("com.example.narrow", name: "Music", minimum: CGSize(width: 600, height: 0))
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        fixture.snap(narrow, tile: Self.rightTile)
        // Asked for the 472 pt the first window left, it kept 600 and stays there, against the right edge: one round of
        // writes into the app, and no second ask for the whole 756 pt zone, which would cover more of its neighbour.
        #expect(narrow.setFrames == [CGRect(x: 1040, y: 37, width: 472, height: 945)])
        #expect(narrow.current == CGRect(x: 912, y: 37, width: 600, height: 945))
        let covered = cleanMyMac.current.map { $0.intersection(narrow.current ?? .null).width }
        #expect(covered == 128, "the overlap is what the window cannot help (600 - 472), not the 284 pt of the whole zone")
        #expect(fixture.notices.last == "Music không thu nhỏ được tới ô này (tối thiểu 600 pt)")
        #expect(fixture.notices.count == 2)
        #expect(fixture.felt == 2, "both snapped")
    }

    @Test func whenLessThanASliverIsLeftTheWindowIsNotEvenAskedForIt() {
        let huge = window("com.example.huge", minimum: CGSize(width: 1400, height: 0))
        fixture.snap(huge, tile: Self.leftTile)
        fixture.snap(music, tile: Self.rightTile)
        #expect(music.setFrames == [CGRect(x: 756, y: 37, width: 756, height: 945)])
        #expect(fixture.notices.count == 1, "only the one that does not fit its own zone")
    }

    @Test func anAppThatRefusesToMoveIsNotAskedAgainAndNothingIsSaid() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        music.accepts = false
        fixture.snap(music, tile: Self.rightTile)
        #expect(music.placements.count == 1)
        #expect(fixture.notices.count == 1)
        #expect(fixture.felt == 1)
        // A window that did not move is not remembered as a neighbour.
        let next = window("com.example.next")
        fixture.snap(next, tile: Self.thirdsTile, zone: 0)
        #expect(next.placements.count == 1)
    }

    // MARK: neighbours nobody can see

    @Test func aMinimisedOrHiddenNeighbourIsIgnoredAndAskedAboutOnlyWhenItReachesTheZone() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        let fitting = window("com.example.fits")
        fixture.snap(fitting, tile: Self.thirdsTile, zone: 2)
        cleanMyMac.isHidden = true
        fixture.snap(music, tile: Self.rightTile)
        #expect(music.current == CGRect(x: 756, y: 37, width: 756, height: 945), "no room kept for a window nobody sees")
        #expect(music.setFrames.count == 1)
        #expect(cleanMyMac.outOfSightChecks == 1)
        #expect(fitting.outOfSightChecks == 0, "a window that does not reach the zone is not worth a question to its app")
        #expect(fixture.logged.contains { $0.hasPrefix("neighbours app=com.apple.Music") && $0.contains("hidden=com.macpaw.CleanMyMac decision=whole") })
    }

    @Test func aHiddenNeighbourIsNeighbourAgainOnceItIsBack() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        cleanMyMac.isHidden = true
        fixture.snap(music, tile: Self.rightTile)
        cleanMyMac.isHidden = false
        let next = window("com.example.next")
        fixture.snap(next, tile: Self.rightTile)
        #expect(next.current == CGRect(x: 1040, y: 37, width: 472, height: 945), "the window was only skipped, not forgotten")
    }

    @Test func aWindowThatFitsItsZoneIsNeverAskedWhetherItIsHidden() {
        fixture.snap(music, tile: Self.leftTile)
        fixture.snap(window("com.example.next"), tile: Self.rightTile)
        #expect(music.outOfSightChecks == 0)
    }

    // MARK: two displays

    @Test func aWindowOnAnotherDisplayIsNeverANeighbour() {
        fixture.addExternalDisplay()
        let wide = window("com.example.wide", minimum: CGSize(width: 1500, height: 0))
        fixture.snap(wide, tile: Self.leftTile, onExternal: true)
        // The external display starts exactly where the MacBook's right half ends.
        fixture.snap(music, tile: Self.rightTile)
        #expect(wide.current == CGRect(x: 1512, y: -335, width: 1500, height: 1335))
        #expect(music.current == CGRect(x: 756, y: 37, width: 756, height: 945))
        #expect(music.setFrames.count == 1)
        let before = window("com.example.before", minimum: CGSize(width: 1000, height: 0))
        fixture.snap(before, tile: Self.rightTile)
        let beside = window("com.example.beside")
        fixture.snap(beside, tile: Self.leftTile, onExternal: true)
        #expect(beside.current == CGRect(x: 1512, y: -335, width: 1280, height: 1335), "same zone as the wide one: stacked")
    }

    @Test func aNeighbourStillNarrowsTheZoneOnItsOwnDisplay() {
        fixture.addExternalDisplay()
        let wide = window("com.example.wide", minimum: CGSize(width: 1500, height: 0))
        let next = window("com.example.next")
        fixture.snap(wide, tile: Self.leftTile, onExternal: true)
        fixture.snap(next, tile: Self.rightTile, onExternal: true)
        // The external display's right half is 2792 to 4072; the wide window reaches 3012.
        #expect(next.current == CGRect(x: 3012, y: -335, width: 1060, height: 1335))
        #expect(!overlap(wide, next))
    }

    // MARK: who is a neighbour

    @Test func aWindowInTheSameZoneIsStackedOnPurposeEvenWhenItLeavesRoomBeside() {
        // A window that cannot grow past 400 pt leaves 356 pt of the left half free: a free part a neighbour would get.
        let small = window("com.example.small")
        small.maximum = CGSize(width: 400, height: 10_000)
        fixture.snap(small, tile: Self.leftTile)
        let same = window("com.example.same")
        fixture.snap(same, tile: Self.leftTile)
        #expect(small.current == CGRect(x: 0, y: 37, width: 400, height: 945))
        #expect(same.current == CGRect(x: 0, y: 37, width: 756, height: 945))
        #expect(same.setFrames.count == 1)
    }

    @Test func neighbourhoodIsAnotherZoneOfTheSameFamily() {
        func target(_ layout: SnapLayout, _ zone: Int = 0) -> SnapTarget { SnapTarget(layout: layout, zone: zone) }
        #expect(target(.leftHalf).isNeighbour(of: target(.rightHalf)))
        #expect(target(.rightHalf).isNeighbour(of: target(.leftHalf)))
        #expect(!target(.leftHalf).isNeighbour(of: target(.leftHalf)))
        #expect(target(.thirds, 0).isNeighbour(of: target(.thirds, 2)))
        #expect(!target(.thirds, 1).isNeighbour(of: target(.thirds, 1)))
        #expect(target(.quarters, 0).isNeighbour(of: target(.quarters, 3)))
        #expect(!target(.quarters, 2).isNeighbour(of: target(.quarters, 2)))
        #expect(!target(.leftHalf).isNeighbour(of: target(.thirds, 0)))
        #expect(!target(.quarters, 0).isNeighbour(of: target(.leftHalf)))
        for layout in [SnapLayout.fullScreen, .focus] {
            #expect(!target(layout).isNeighbour(of: target(layout)))
            #expect(!target(layout).isNeighbour(of: target(.leftHalf)))
            #expect(!target(.leftHalf).isNeighbour(of: target(layout)))
        }
    }

    // MARK: slow apps

    @Test func anAppThatAppliesItsSizeLateIsJudgedByTheSizeItEndsWithAndRememberedByIt() {
        let slow = FakeWindow(app: SnapApp(bundleID: "com.example.slow", name: "Slow"), minimum: CGSize(width: 1040, height: 0))
        slow.appliesSizeLate = true
        let next = window("com.example.next")
        fixture.snap(slow, tile: Self.leftTile)
        #expect(slow.current == CGRect(x: 0, y: 37, width: 1040, height: 945), "the size it really has")
        // Remembered at that size, not at the 800 x 600 it was read at first.
        fixture.snap(next, tile: Self.rightTile)
        #expect(next.current == CGRect(x: 1040, y: 37, width: 472, height: 945))
        #expect(fixture.notices == ["Slow không thu nhỏ được tới ô này (tối thiểu 1040 pt)"])
    }

    @Test func aSlowAppThatTakesTheZoneSizeGetsNoNoticeFromItsOldSize() {
        let slow = FakeWindow(app: SnapApp(bundleID: "com.example.slow", name: "Slow"))
        slow.appliesSizeLate = true
        fixture.snap(slow, tile: Self.thirdsTile, zone: 0)
        #expect(slow.current == CGRect(x: 0, y: 37, width: 504, height: 945))
        #expect(fixture.notices.isEmpty, "it was read at its old 800 pt width first")
        #expect(fixture.logged.last?.contains("actual=504x945") == true)
    }

    // MARK: the notice

    @Test func aSizeLargerThanTheZoneByMoreThanTwoPointsIsSaid() {
        let fits = window("com.example.fits", minimum: CGSize(width: 506, height: 0))
        let over = window("com.example.over", minimum: CGSize(width: 507, height: 0))
        fixture.snap(fits, tile: Self.thirdsTile, zone: 0)
        #expect(fixture.notices.isEmpty, "2 pt wider than the 504 pt zone is rounding")
        fixture.snap(over, tile: Self.thirdsTile, zone: 2)
        #expect(fixture.notices == ["com.example.over không thu nhỏ được tới ô này (tối thiểu 507 pt)"])
    }

    @Test func aWindowThatFitsItsZoneSaysNothing() {
        fixture.snap(music, tile: Self.leftTile)
        #expect(fixture.notices.isEmpty)
    }

    @Test func aRefusedMoveSaysNothingAndIsNotRemembered() {
        cleanMyMac.accepts = false
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        #expect(fixture.notices.isEmpty)
        fixture.snap(music, tile: Self.rightTile)
        #expect(music.setFrames == [CGRect(x: 756, y: 37, width: 756, height: 945)])
    }

    // MARK: the log

    @Test func eachPlacementAndTheNeighbourDecisionAreLoggedWithoutAnyTitle() {
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        fixture.snap(music, tile: Self.rightTile)
        #expect(fixture.logged == [
            "neighbours app=com.macpaw.CleanMyMac layout=leftHalf zone=0 known=0 adjacent=none hidden=none decision=whole",
            "placed app=com.macpaw.CleanMyMac layout=leftHalf zone=0 ask=zone frame=0,37,756,945 requested=756x945 actual=1040x945 origin=0,37 landed=0,37 oversize=yes refused=no",
            "neighbours app=com.apple.Music layout=rightHalf zone=0 known=1 adjacent=com.macpaw.CleanMyMac hidden=none decision=part free=1040,37,472,945",
            "placed app=com.apple.Music layout=rightHalf zone=0 ask=part frame=1040,37,472,945 requested=472x945 actual=472x945 origin=1040,37 landed=1040,37 oversize=no refused=no",
        ])
    }

    @Test func aFitThatFailedAndTheOverlapThatStaysAreLogged() {
        let narrow = window("com.example.narrow", minimum: CGSize(width: 600, height: 0))
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        fixture.snap(narrow, tile: Self.rightTile)
        let lines = Array(fixture.logged.dropFirst(2))
        #expect(lines == [
            "neighbours app=com.example.narrow layout=rightHalf zone=0 known=1 adjacent=com.macpaw.CleanMyMac hidden=none decision=part free=1040,37,472,945",
            "placed app=com.example.narrow layout=rightHalf zone=0 ask=part frame=1040,37,472,945 requested=472x945 actual=600x945 origin=912,37 landed=912,37 oversize=yes refused=no",
            "overlaps app=com.example.narrow with=com.macpaw.CleanMyMac layout=leftHalf zone=0 by=128x945 neighbour-moved=no",
        ])
    }

    @Test func aWindowThatSpillsOverARegisteredNeighbourIsLoggedAsOverlappingAndTheNeighbourIsLeftAlone() {
        fixture.snap(music, tile: Self.rightTile)
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        #expect(fixture.logged.last == "overlaps app=com.macpaw.CleanMyMac with=com.apple.Music layout=rightHalf zone=0 by=284x945 neighbour-moved=no")
    }

    @Test func aPlacementThatSwitchedTheEnhancedInterfaceOffSaysSoAndOtherPlacementsDoNot() {
        let chrome = FakeWindow(app: SnapApp(bundleID: "com.google.Chrome", name: "Google Chrome"))
        chrome.enhancedUI = true
        fixture.snap(chrome, tile: Self.rightTile)
        #expect(fixture.logged.last == "placed app=com.google.Chrome layout=rightHalf zone=0 ask=zone frame=756,37,756,945 requested=756x945 actual=756x945 origin=756,37 landed=756,37 oversize=no refused=no enhancedUI=1")
        fixture.snap(music, tile: Self.leftTile)
        #expect(fixture.logged.last?.contains("enhancedUI") == false)
    }

    @Test func aRefusedMoveIsLoggedAsRefused() {
        music.accepts = false
        fixture.snap(music, tile: Self.rightTile)
        #expect(fixture.logged.last?.hasSuffix("oversize=no refused=yes") == true)
    }

    @Test func aWindowWhoseSizeCannotBeReadIsLoggedWithQuestionMarks() {
        let mute = FakeWindow(app: SnapApp(bundleID: nil, name: nil))
        mute.goesSilentOnceMoved = true
        fixture.snap(mute, tile: Self.rightTile)
        #expect(fixture.logged.last == "placed app=? layout=rightHalf zone=0 ask=zone frame=756,37,756,945 requested=756x945 actual=? origin=? landed=? oversize=no refused=no")
        #expect(fixture.notices.isEmpty)
    }

    @Test func logLinesHoldNothingButNamedValuesOfAnApp() {
        let secret = FakeWindow(app: SnapApp(bundleID: "com.example.app", name: "Tên riêng của ứng dụng"), minimum: CGSize(width: 1040, height: 0))
        fixture.snap(secret, tile: Self.leftTile)
        fixture.snap(music, tile: Self.rightTile)
        fixture.snap(window("com.example.third"), tile: Self.thirdsTile, zone: 1)
        #expect(fixture.logged.count >= 6)
        for line in fixture.logged {
            #expect(!line.contains("Tên riêng"), "\(line)")
            let tokens = line.split(separator: " ")
            #expect(["neighbours", "placed", "overlaps"].contains(String(tokens[0])), "\(line)")
            for token in tokens.dropFirst() {
                let parts = token.split(separator: "=", maxSplits: 1)
                #expect(parts.count == 2, "\(token) in \(line)")
                #expect(parts.last?.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".,x?+-".contains($0)) } == true, "\(token) in \(line)")
            }
        }
    }

    // MARK: vertical and two-thirds neighbours

    @Test func topAndBottomHalvesAreNeighboursAndYieldRoom() {
        let tall = window("com.example.tall", minimum: CGSize(width: 0, height: 600))
        let lower = window("com.example.lower")
        fixture.snap(tall, tile: Self.topTile)
        fixture.snap(lower, tile: Self.bottomTile)
        // Visible height is 945: tall takes 600 from top (y: 37..637), lower takes remaining 345 (y: 637..982)
        #expect(tall.current == CGRect(x: 0, y: 37, width: 1512, height: 600))
        #expect(lower.current == CGRect(x: 0, y: 637, width: 1512, height: 345))
        #expect(!overlap(tall, lower))
    }

    @Test func leftTwoThirdsAndRightThirdAreNeighbours() {
        let left23 = window("com.example.left23")
        let right13 = window("com.example.right13")
        fixture.snap(left23, tile: Self.leftTwoThirdsTile)
        fixture.snap(right13, tile: Self.thirdsTile, zone: 2)
        #expect(left23.current == CGRect(x: 0, y: 37, width: 1008, height: 945))
        #expect(right13.current == CGRect(x: 1008, y: 37, width: 504, height: 945))
        #expect(!overlap(left23, right13))
    }

    @Test func leftTwoThirdsAndRightTwoThirdsOverlapOnPurposeAndAreNotNeighbours() {
        let targetLeft = SnapTarget(layout: .leftTwoThirds, zone: 0)
        let targetRight = SnapTarget(layout: .rightTwoThirds, zone: 0)
        #expect(!targetLeft.isNeighbour(of: targetRight))
        #expect(!targetRight.isNeighbour(of: targetLeft))
    }
}
