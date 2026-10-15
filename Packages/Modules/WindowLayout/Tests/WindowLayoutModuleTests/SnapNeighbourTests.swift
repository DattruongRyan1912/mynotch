import CoreGraphics
import Foundation
import Testing
@testable import WindowLayoutModule

/// Windows snapped one after the other, through the whole session (tiles, drop, settle delay), with fake windows that keep
/// a smallest size like real apps do. The MacBook's visible area is 1512 x 945 below the 37 pt menu bar; tiles are
/// `SnapLayout.allCases`: 0 left half, 1 right half, 2 full screen, 3 quarters, 4 thirds, 5 focus.
@Suite struct SnapNeighbourTests {
    let fixture = SessionFixture()
    let cleanMyMac = FakeWindow(app: SnapApp(bundleID: "com.macpaw.CleanMyMac", name: "CleanMyMac"), minimum: CGSize(width: 1040, height: 0))
    let music = FakeWindow(app: SnapApp(bundleID: "com.apple.Music", name: "Music"))

    static let leftTile = 0, rightTile = 1, quartersTile = 3, thirdsTile = 4

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
        fixture.snap(focus, tile: 5)
        fixture.snap(full, tile: 2)
        #expect(focus.current == CGRect(x: 252, y: 37, width: 1008, height: 945))
        #expect(full.current == CGRect(x: 0, y: 37, width: 1512, height: 945))
    }

    // MARK: when even the free part is too small

    @Test func aWindowThatCannotShrinkToTheFreePartTakesItsOwnZoneAndSaysSo() {
        let narrow = window("com.example.narrow", name: "Music", minimum: CGSize(width: 600, height: 0))
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        fixture.snap(narrow, tile: Self.rightTile)
        // Tried the 472 pt the first window left, kept 600, then went where the layout says.
        #expect(narrow.setFrames == [CGRect(x: 1040, y: 37, width: 472, height: 945), CGRect(x: 756, y: 37, width: 756, height: 945)])
        #expect(narrow.current == CGRect(x: 756, y: 37, width: 756, height: 945))
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
            "neighbours app=com.macpaw.CleanMyMac layout=leftHalf zone=0 known=0 adjacent=none decision=whole",
            "placed app=com.macpaw.CleanMyMac layout=leftHalf zone=0 ask=zone frame=0,37,756,945 requested=756x945 actual=1040x945 origin=0,37 landed=0,37 oversize=yes refused=no",
            "neighbours app=com.apple.Music layout=rightHalf zone=0 known=1 adjacent=com.macpaw.CleanMyMac decision=part free=1040,37,472,945",
            "placed app=com.apple.Music layout=rightHalf zone=0 ask=part frame=1040,37,472,945 requested=472x945 actual=472x945 origin=1040,37 landed=1040,37 oversize=no refused=no",
        ])
    }

    @Test func aFitThatFailedAndAnOverlapThatStaysAreLogged() {
        let narrow = window("com.example.narrow", minimum: CGSize(width: 600, height: 0))
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        fixture.snap(narrow, tile: Self.rightTile)
        let lines = Array(fixture.logged.dropFirst(2))
        #expect(lines == [
            "neighbours app=com.example.narrow layout=rightHalf zone=0 known=1 adjacent=com.macpaw.CleanMyMac decision=part free=1040,37,472,945",
            "placed app=com.example.narrow layout=rightHalf zone=0 ask=part frame=1040,37,472,945 requested=472x945 actual=600x945 origin=912,37 landed=912,37 oversize=yes refused=no",
            "placed app=com.example.narrow layout=rightHalf zone=0 ask=fallback frame=756,37,756,945 requested=756x945 actual=756x945 origin=756,37 landed=756,37 oversize=no refused=no",
            "overlaps app=com.example.narrow with=com.macpaw.CleanMyMac layout=leftHalf zone=0 by=284x945 neighbour-moved=no",
        ])
    }

    @Test func aWindowThatSpillsOverARegisteredNeighbourIsLoggedAsOverlappingAndTheNeighbourIsLeftAlone() {
        fixture.snap(music, tile: Self.rightTile)
        fixture.snap(cleanMyMac, tile: Self.leftTile)
        #expect(fixture.logged.last == "overlaps app=com.macpaw.CleanMyMac with=com.apple.Music layout=rightHalf zone=0 by=284x945 neighbour-moved=no")
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
}
