import AppKit
import MyNotchCore
import NotchUI
import SwiftUI
import Testing
@testable import PetModule

/// The cat in the top row of the notch: on a virtual notch one lane across its body, on a hardware notch two, one each side of the camera
/// (which is read from the geometry and the screen, never written down).
@Suite(.serialized) @MainActor struct CatBodyTests {
    // MARK: Where the camera is

    @Test func theMacOfTheUserHasACameraOfTwoHundredAndTwentyPointsAndTheGeometryAgreesWithTheScreen() throws {
        let geometry = Screens.hardware
        #expect(geometry.kind == .hardware)
        #expect(geometry.notchSize == CGSize(width: 220, height: 38))
        #expect(geometry.centerOffset == 0)
        // What the screen reports: the menu bar's areas left and right of the camera, which end and begin at its edges.
        let measured = try #require(Cutout.measured(auxiliaryLeft: Screens.macAreas.left, auxiliaryRight: Screens.macAreas.right))
        #expect(measured == 790...1010)
        // What the geometry says, in the row the notch makes for the cat: the same two edges.
        let row = Screens.row(of: geometry)
        #expect(row == 420, "the camera and a hundred points each side")
        let rowLeft = Screens.mac.frame.midX + geometry.centerOffset - row / 2
        let geometric = Cutout.geometric(rowWidth: row, cameraWidth: geometry.notchSize.width)
        #expect(geometric == 100...320)
        #expect(rowLeft + geometric.lowerBound == measured.lowerBound && rowLeft + geometric.upperBound == measured.upperBound)
    }

    @Test func aScreenWithNoCameraHasNoCutoutToMeasureAndAMisplacedPairOfAreasIsNone() {
        #expect(Cutout.measured(auxiliaryLeft: nil, auxiliaryRight: nil) == nil)
        #expect(Cutout.measured(auxiliaryLeft: CGRect(x: 0, y: 0, width: 800, height: 30), auxiliaryRight: nil) == nil)
        #expect(Cutout.measured(auxiliaryLeft: CGRect(x: 0, y: 0, width: 800, height: 30), auxiliaryRight: CGRect(x: 790, y: 0, width: 800, height: 30)) == nil)
    }

    // MARK: What the cat asks of the notch

    @Test func aHardwareNotchIsAskedForTheCameraAndAHundredPointsEachSideAndAVirtualOneForTheWidthOfItsBody() {
        let hardware = CatBodyLayout(kind: .hardware, place: .portal)
        #expect(CatBodyLayout.wingRoom == 100, "not so much that it covers more of the menu bar than it has to")
        #expect(hardware.requestedWidth(cameraWidth: 220) == 420)
        #expect(hardware.requestedWidth(cameraWidth: 185) == 385, "from the camera of the screen it is on")
        let virtual = CatBodyLayout(kind: .virtual, place: .portal)
        #expect(virtual.requestedWidth(cameraWidth: 0) == 280 && virtual.requestedWidth(cameraWidth: 185) == 280)
    }

    @Test func theCatPlaysInTheBodyEverywhereButUnderAHardwareNotchWhenTheStripIsChosen() {
        #expect(CatBodyLayout(kind: .hardware, place: .portal).playsInBody)
        #expect(!CatBodyLayout(kind: .hardware, place: .strip).playsInBody)
        #expect(CatBodyLayout(kind: .virtual, place: .portal).playsInBody)
        #expect(CatBodyLayout(kind: .virtual, place: .strip).playsInBody, "a virtual notch has room in its body: no strip there")
    }

    func hostedBody(_ geometry: NotchGeometry, place: PlayPlace, onScreen: Bool = true) -> (CatStage, NSWindow, [CGFloat]) {
        let rig = BodyRig(geometry: geometry, place: place)
        let asked = AskedWidths()
        let view = CatBodyView(stage: rig.stage, place: place)
            .environment(\.notchGeometry, geometry)
            .environment(\.notchIsOnScreen, onScreen)
            .frame(width: rig.rowWidth, height: geometry.notchSize.height)
            .onNotchStripWidth { asked.values.append($0) }
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: rig.rowWidth, height: geometry.notchSize.height), styleMask: .borderless, backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        keep.append((rig, window))
        return (rig.stage, window, asked.values)
    }

    final class AskedWidths { var values: [CGFloat] = [] }
    var keep: [(BodyRig, NSWindow)] { get { Self.kept } nonmutating set { Self.kept = newValue } }
    static var kept: [(BodyRig, NSWindow)] = []

    @Test func theBodyAsksTheNotchForItsWidthByTheKindOfNotchItIsIn() {
        let hardware = hostedBody(Screens.hardware, place: .portal)
        #expect(hardware.2.last == 420 - 2 * NotchTokens.stripPadding, "the row of 420 less the padding a strip's width has")
        let virtual = hostedBody(Screens.pill, place: .portal)
        #expect(virtual.2.last == 280 - 2 * NotchTokens.stripPadding)
        let strip = hostedBody(Screens.hardware, place: .strip)
        #expect(strip.2.isEmpty || strip.2.allSatisfy { $0 == 0 }, "with the strip chosen a hardware notch is asked for nothing")
        hardware.1.contentView = nil
        virtual.1.contentView = nil
        strip.1.contentView = nil
    }

    @Test func theCatsViewsAreInTheTreeOnlyWhileTheNotchIsOnScreenAndOnlyWhereTheCatPlaysInTheBody() {
        let hardware = hostedBody(Screens.hardware, place: .portal)
        #expect(hardware.0.attachedHosts.count == 2, "a view each side of the camera")
        let pill = hostedBody(Screens.pill, place: .portal)
        #expect(pill.0.attachedHosts.count == 1, "one lane across the body of a virtual notch")
        let strip = hostedBody(Screens.hardware, place: .strip)
        #expect(strip.0.attachedHosts.isEmpty, "none: the strip has the cat")
        let stripOnVirtual = hostedBody(Screens.notch, place: .strip)
        #expect(stripOnVirtual.0.attachedHosts.count == 1, "but a virtual notch keeps the cat in its body")
        let hidden = hostedBody(Screens.hardware, place: .portal, onScreen: false)
        #expect(hidden.0.attachedHosts.isEmpty && !hidden.0.isAlive, "a notch that cannot be seen has no cat in it")
        for hosted in [hardware, pill, strip, stripOnVirtual, hidden] { hosted.1.contentView = nil }
        #expect(!hardware.0.isAlive && !pill.0.isAlive)
    }

    // MARK: The views

    @Test func aHardwareNotchGetsTwoViewsOneEachSideOfTheCameraThatEndAndBeginAtItsEdges() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.show()
        let left = try #require(rig.container.leftWing)
        let right = try #require(rig.container.rightWing)
        #expect(rig.container.lane == nil && rig.hosts.count == 2)
        #expect(left.role == .leftWing && right.role == .rightWing && left.partner === right && right.partner === left)
        // In the row's own coordinates: the camera is from 100 to 320.
        #expect(left.frame == CGRect(x: 0, y: 0, width: 100, height: 38))
        #expect(right.frame == CGRect(x: 320, y: 0, width: 100, height: 38))
        // And on the screen: they end and begin where the camera does.
        let leftOnScreen = try #require(left.screenFrame)
        let rightOnScreen = try #require(right.screenFrame)
        #expect(leftOnScreen.maxX == 790 && rightOnScreen.minX == 1010)
        #expect(rightOnScreen.minX - leftOnScreen.maxX == Screens.hardware.notchSize.width)
        #expect(rig.stage.attachedHosts.count == 2)
    }

    @Test func theCameraIsReadFromTheScreenAndNotFromTheWidthOfTheRowWhenTheScreenSaysWhereItIs() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        // The areas of this screen are not the middle of the row: the camera is where the screen says.
        rig.container.screenAreas = { _ in (CGRect(x: 0, y: 0, width: 760, height: 38), CGRect(x: 990, y: 0, width: 800, height: 38)) }
        rig.show()
        let left = try #require(rig.container.leftWing)
        let right = try #require(rig.container.rightWing)
        // The row begins at 690: the camera is from 760 to 990 on the screen, which is 70 to 300 in the row.
        #expect(left.frame.width == 70 && right.frame.minX == 300 && right.frame.width == 120)
        // With no camera reported the geometry says: the middle.
        let other = BodyRig(geometry: Screens.hardware)
        other.container.screenAreas = { _ in nil }
        other.show()
        #expect(other.container.leftWing?.frame.width == 100 && other.container.rightWing?.frame.minX == 320)
    }

    @Test func aVirtualNotchGetsOneViewAcrossTheWholeBodyAndNoStrip() throws {
        for geometry in [Screens.notch, Screens.pill] {
            let rig = BodyRig(geometry: geometry)
            rig.show()
            let lane = try #require(rig.container.lane)
            #expect(rig.hosts.count == 1 && rig.container.leftWing == nil && rig.container.rightWing == nil)
            #expect(lane.role == .lane)
            #expect(lane.frame == rig.container.bounds, "the whole row")
            #expect(rig.rowWidth >= 280, "wide enough to walk in: \(rig.rowWidth)")
            #expect(lane.field.crossing == nil && lane.field.scale == 1)
            #expect(lane.lane.travel > 220)
        }
    }

    @Test func theCatInTheBodyOfAPillIsDrawnAWholeNumberOfPointsToThePixelAndInsideTheBody() throws {
        for (geometry, scale) in [(Screens.pill, 1), (Screens.notch, 1), (Screens.tallPill, 2)] {
            let rig = BodyRig(geometry: geometry)
            rig.show()
            rig.stage.attach(rig.hosts[0])
            rig.advance(1)
            let lane = try #require(rig.container.lane)
            let size = lane.sprite.bounds.size
            #expect(size == CGSize(width: 32 * scale, height: 24 * scale), "\(scale) points to the pixel")
            #expect(lane.sprite.magnificationFilter == .nearest && lane.sprite.minificationFilter == .nearest)
            #expect(lane.sprite.position.x == lane.sprite.position.x.rounded() && lane.sprite.position.y == lane.sprite.position.y.rounded())
            let frame = CGRect(origin: lane.sprite.position, size: size)
            #expect(lane.bounds.contains(frame), "the cat is inside the body: \(frame) in \(lane.bounds)")
            #expect(frame.minY == ((lane.bounds.height - size.height) / 2).rounded(.down), "in the middle of its height")
        }
    }

    // MARK: Clicks

    @Test func aClickReachesTheCatOnlyWhereTheCatIsAndEverythingElseInTheRowIsTheNotchsOwn() throws {
        for geometry in [Screens.hardware, Screens.pill] {
            let rig = BodyRig(geometry: geometry)
            rig.show()
            rig.advance(1)
            // The view the cat is in: the one whose bounds hold the middle of it.
            let host = try #require(rig.hosts.first {
                let frame = ($0.sprite.presentation() ?? $0.sprite).frame
                return $0.isShowingCat && $0.bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
            })
            let drawn = (host.sprite.presentation() ?? host.sprite).frame
            // A point of the row in the container's own coordinates (a view hit-tests in its superview's).
            let onCat = rig.container.convert(CGPoint(x: drawn.midX, y: drawn.midY), from: host)
            #expect(rig.container.hitTest(rig.window.contentView.map { rig.container.convert(onCat, to: $0) } ?? onCat) === host, "\(geometry.kind)")
            // The far end of the row, where the cat is not.
            let away = CGPoint(x: rig.container.bounds.width - 3, y: 1)
            #expect(rig.container.hitTest(rig.window.contentView.map { rig.container.convert(away, to: $0) } ?? away) == nil, "\(geometry.kind)")
            // Nowhere outside the row.
            let outside = CGPoint(x: -20, y: 5)
            #expect(rig.container.hitTest(rig.window.contentView.map { rig.container.convert(outside, to: $0) } ?? outside) == nil)
        }
    }

    // MARK: Resting, moving, leaving

    @Test func withReduceMotionTheCatSitsInTheLeftViewBesideTheCameraWithOnlyItsEyesMoving() throws {
        let rig = BodyRig(geometry: Screens.hardware, reducesMotion: true)
        rig.show()
        rig.advance(5)
        #expect(rig.stage.isAlive && !rig.stage.isTicking, "nothing wakes for a cat that does not move")
        let left = try #require(rig.container.leftWing)
        let right = try #require(rig.container.rightWing)
        for host in [left, right] {
            #expect(host.sprite.animationKeys() == [CatSpriteView.framesKey], "only its eyes")
            #expect(host.prop.isHidden && host.portal.isHidden)
        }
        let field = left.field
        let crossing = try #require(field.crossing)
        #expect(left.sprite.position.x == field.lane.restingX && field.lane.restingX <= crossing.lowerBound)
        let place = CGRect(origin: left.sprite.position, size: left.sprite.bounds.size)
        #expect(left.bounds.contains(place), "whole in the left view")
        #expect(!CGRect(origin: right.sprite.position, size: right.sprite.bounds.size).intersects(right.bounds), "and not in the right")
    }

    @Test func aVirtualNotchRestsTheCatInTheMiddleOfItsBody() throws {
        let rig = BodyRig(geometry: Screens.pill, reducesMotion: true)
        rig.show()
        let lane = try #require(rig.container.lane)
        #expect(lane.sprite.position.x == lane.field.lane.restingX.rounded())
        #expect(lane.sprite.position.x > rig.rowWidth / 2 - 40 && lane.sprite.position.x < rig.rowWidth / 2)
    }

    @Test func theViewsAreTakenOutWithTheNotchAndTheCatStopsWithThem() {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.show()
        rig.advance(2)
        #expect(rig.stage.isAlive && rig.stage.attachedHosts.count == 2)
        rig.hide()
        #expect(!rig.stage.isAlive && rig.stage.attachedHosts.isEmpty && !rig.stage.isTicking)
        #expect(rig.scheduler.pendingCount == 0)
        for host in rig.hosts { #expect(!host.isAnimating && !host.isShowingCat) }
    }

    @Test func aNotchThatBecomesAnotherKindOfNotchGetsTheViewsThatKindNeeds() throws {
        let rig = BodyRig(geometry: Screens.hardware)
        rig.show()
        #expect(rig.stage.attachedHosts.count == 2)
        rig.container.configure(geometry: Screens.pill)
        rig.container.layoutSubtreeIfNeeded()
        #expect(rig.container.lane != nil && rig.container.leftWing == nil && rig.container.rightWing == nil)
        #expect(rig.stage.attachedHosts.count == 1 && rig.stage.attachedHosts.first?.role == .lane, "the wings left and the lane came")
        rig.container.configure(geometry: Screens.hardware)
        rig.container.layoutSubtreeIfNeeded()
        #expect(rig.container.lane == nil && rig.stage.attachedHosts.count == 2)
    }

    @Test func aNotchThatGrowsMovesTheCatWithItAndTheCatIsShownAgainOnlyWhenItsPlaceInItChanges() throws {
        // The notch's window is as wide as the panel, 900 points, with the row in the middle of it, and the camera is where the screen has it.
        let rig = BodyRig(geometry: Screens.hardware, width: 360)
        rig.window.setFrame(CGRect(x: 450, y: rig.window.frame.minY, width: 900, height: 38), display: false)
        rig.container.frame = CGRect(x: 270, y: 0, width: 360, height: 38)
        rig.show()
        rig.advance(1)
        let left = try #require(rig.container.leftWing)
        #expect(left.frame.width == CGFloat(70), "the notch has not grown to what the cat asked for yet: 70 points each side")
        let shown = rig.stage.presentations
        // The notch springs wider: the row is 420 and the cat's views are a hundred each side.
        rig.container.frame = CGRect(x: 240, y: 0, width: 420, height: 38)
        rig.container.layoutSubtreeIfNeeded()
        #expect(left.frame.width == CGFloat(100), "\(left.frame)")
        #expect(rig.stage.presentations > shown, "the cat is shown again in the new lane")
        let after = rig.stage.presentations
        // A layout that changes nothing shows nothing again.
        rig.container.needsLayout = true
        rig.container.layoutSubtreeIfNeeded()
        #expect(rig.stage.presentations == after)
    }

    @Test func aHeadThatPeeksComesUpFromTheBottomOfTheBodyAndIsCutOffThereAsItIsAtTheEdgeOfAStrip() throws {
        for (geometry, scale) in [(Screens.pill, 1), (Screens.tallPill, 2)] {
            let rig = BodyRig(geometry: geometry)
            rig.show()
            let lane = try #require(rig.container.lane)
            lane.show(plan: CatPlan(move: .peek, facing: .right, from: 0.5, to: 0.5, began: 0, duration: 1), elapsed: 0, coat: .tabby)
            #expect(lane.sprite.position.y == CGFloat(-2 * scale), "below the bottom of the body, which cuts it off: \(lane.sprite.position.y)")
        }
        let strip = CatSpriteView(stage: CatStage(scheduler: ManualSchedulerStub.make()))
        strip.frame = CGRect(x: 0, y: 0, width: 300, height: 26)
        strip.show(plan: CatPlan(move: .peek, facing: .right, from: 0.5, to: 0.5, began: 0, duration: 1), elapsed: 0, coat: .tabby)
        #expect(strip.sprite.position.y == CatSpriteView.floor - CatSpriteView.peekSink, "and in a strip it is as it was")
    }
}
