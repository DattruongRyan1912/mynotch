import CoreGraphics
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The strip an activity draws under the collapsed notch: the shape grows downward inside the fixed panel.
@Suite struct NotchStripTests {
    let macBook = NotchGeometryTests.macBook14
    let external = NotchGeometryTests.external

    func geometry(_ screen: ScreenDescriptor, _ config: NotchLayoutConfig = NotchLayoutConfig()) -> NotchGeometry {
        NotchGeometry(screen: screen, config: config)
    }

    @Test func aCompactNotchWithAStripIsTallerByTheStripAndNotWider() {
        let geometry = geometry(macBook)
        let plain = geometry.shapeSize(for: .compact)
        let withStrip = geometry.shapeSize(for: .compact, bottomHeight: 36)
        #expect(plain == CGSize(width: 325, height: 32))
        #expect(withStrip == CGSize(width: 325, height: 68))
    }

    @Test func theStripKeepsTheCompactCornerRadii() {
        let geometry = geometry(macBook)
        #expect(geometry.cornerRadii(for: .compact) == (6, 10))
    }

    @Test func noStripRequestedChangesNothing() {
        let geometry = geometry(macBook)
        for state in [NotchState.closed, .compact, .open("a"), .open(nil), .toast] {
            #expect(geometry.shapeSize(for: state, bottomHeight: 0) == geometry.shapeSize(for: state))
            #expect(geometry.hitRect(for: state, bottomHeight: 0, in: macBook.frame) == geometry.hitRect(for: state, in: macBook.frame))
            #expect(geometry.dragHitRect(for: state, bottomHeight: 0, in: macBook.frame) == geometry.dragHitRect(for: state, in: macBook.frame))
        }
    }

    @Test func onlyTheCompactNotchShowsAStrip() {
        let geometry = geometry(macBook)
        for state in [NotchState.closed, .open("a"), .open(nil), .toast] {
            #expect(geometry.bottomHeight(for: state, requested: 36) == 0, "\(state)")
            #expect(geometry.shapeSize(for: state, contentHeight: 200, bottomHeight: 36) == geometry.shapeSize(for: state, contentHeight: 200))
            #expect(geometry.hitRect(for: state, bottomHeight: 36, in: macBook.frame) == geometry.hitRect(for: state, in: macBook.frame))
        }
        #expect(geometry.bottomHeight(for: .compact, requested: 36) == 36)
    }

    @Test func theHitRectFollowsTheTallerShape() {
        let geometry = geometry(macBook)
        let rect = geometry.hitRect(for: .compact, bottomHeight: 36, in: macBook.frame)
        #expect(rect == CGRect(x: 754.5 - 162.5 - 8, y: 982 - 68 - 8, width: 325 + 16, height: 68 + 8 + 1))
        let plain = geometry.hitRect(for: .compact, in: macBook.frame)
        #expect(plain.height + 36 == rect.height)
        #expect(plain.minX == rect.minX && plain.width == rect.width)
        // A point inside the strip counts as inside only with the strip.
        let inStrip = CGPoint(x: 754.5, y: 982 - 50)
        #expect(rect.contains(inStrip))
        #expect(!plain.contains(inStrip))
    }

    @Test func theDragHitRectFollowsTheTallerShape() {
        let geometry = geometry(macBook)
        let rect = geometry.dragHitRect(for: .compact, bottomHeight: 36, in: macBook.frame)
        #expect(rect == CGRect(x: 754.5 - 162.5 - 40, y: 982 - 68 - 40, width: 325 + 80, height: 68 + 40 + 1))
    }

    @Test func aNotchlessDisplayGetsTheSameStripUnderThePill() {
        let geometry = geometry(external)
        #expect(geometry.shapeSize(for: .compact, bottomHeight: 36) == CGSize(width: 325, height: 25 + 36))
        let rect = geometry.hitRect(for: .compact, bottomHeight: 36, in: external.frame)
        #expect(rect == CGRect(x: 1512 + 960 - 162.5 - 8, y: 1080 - 61 - 8, width: 325 + 16, height: 61 + 8 + 1))
    }

    @Test func theStripFollowsAWiderCompactPill() {
        let wide = geometry(macBook, NotchLayoutConfig(compactSideWidth: 90))
        #expect(wide.shapeSize(for: .compact, bottomHeight: 36).width == wide.shapeSize(for: .compact).width)
        #expect(wide.shapeSize(for: .compact, bottomHeight: 36).width > 325)
    }

    @Test func theRequestedHeightIsClampedToSomethingTheFixedPanelHolds() {
        let geometry = geometry(macBook)
        #expect(geometry.bottomHeight(for: .compact, requested: -5) == 0)
        #expect(geometry.bottomHeight(for: .compact, requested: .nan) == 0)
        #expect(geometry.bottomHeight(for: .compact, requested: .infinity) == NotchGeometry.maxBottomHeight)
        #expect(geometry.bottomHeight(for: .compact, requested: 10_000) == NotchGeometry.maxBottomHeight)
        #expect(geometry.bottomHeight(for: .compact, requested: 0.5) == 0.5)
    }

    @Test func thePanelFrameDoesNotDependOnTheStripAndAlwaysHoldsIt() {
        let screens = [macBook, external, NotchGeometryTests.externalAboveLeft]
        let configs = [
            NotchLayoutConfig(),
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, compactSideWidth: 120, openWidth: 720),
            NotchLayoutConfig(virtualNotchWidth: 120, virtualNotchHeight: 24, openWidth: 480),
        ]
        for screen in screens {
            for config in configs {
                let geometry = geometry(screen, config)
                let panel = geometry.panelFrame(in: screen.frame)
                for requested in [0, 1, 36, 80, 500, CGFloat.infinity] as [CGFloat] {
                    let size = geometry.shapeSize(for: .compact, bottomHeight: requested)
                    let rect = CGRect(
                        x: screen.frame.midX + geometry.centerOffset - size.width / 2, y: screen.frame.maxY - size.height,
                        width: size.width, height: size.height
                    )
                    #expect(panel.contains(rect), "strip \(requested) fits the panel on \(screen.frame)")
                    #expect(geometry.panelFrame(in: screen.frame) == panel)
                }
            }
        }
    }

    /// The panel is never resized, so a strip coming or going is only a change of the shape inside it. Whatever the
    /// spring does between the two heights (including a little overshoot) stays a visible shape inside the panel.
    @Test func showingAndHidingAStripNeverPassesThroughAHiddenOrOutOfPanelFrame() {
        let screens = [macBook, external]
        for screen in screens {
            let geometry = geometry(screen)
            let panel = geometry.panelFrame(in: screen.frame)
            let hidden = geometry.shapeSize(for: .compact)
            let shown = geometry.shapeSize(for: .compact, bottomHeight: 36)
            let show = (0 ... 20).map { hidden.height + (shown.height - hidden.height) * (Double($0) / 20 * 1.03) }
            let hide = Array(show.reversed())
            for height in show + hide {
                let rect = CGRect(
                    x: screen.frame.midX + geometry.centerOffset - shown.width / 2, y: screen.frame.maxY - height,
                    width: shown.width, height: height
                )
                #expect(rect.width > 0 && rect.height >= hidden.height, "the notch never shrinks below the pill")
                #expect(panel.contains(rect))
            }
            #expect(show.first == hidden.height && hide.last == hidden.height)
        }
    }

    // MARK: ActivityCenter side

    func makeActivity(id: String = "a", bottom: Bool = true, height: CGFloat = 36) -> LiveActivity {
        LiveActivity(
            id: id, leading: AnyView(Color.clear), trailing: AnyView(Color.clear),
            bottom: bottom ? AnyView(Color.clear) : nil, bottomHeight: height
        )
    }

    @Test func theCenterReportsTheCurrentActivitysStripHeight() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        #expect(center.stripHeight == 0)
        center.set(makeActivity(bottom: false), from: "media")
        #expect(center.stripHeight == 0)
        center.set(makeActivity(), from: "media")
        #expect(center.stripHeight == 36)
        center.set(makeActivity(height: 0), from: "media")
        #expect(center.stripHeight == 0)
        center.set(makeActivity(height: 44), from: "media")
        #expect(center.stripHeight == 44)
        center.clear(id: "a", from: "media")
        #expect(center.stripHeight == 0)
    }

    @Test func onlyTheCurrentActivitysStripCounts() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(makeActivity(id: "strip"), from: "media")
        center.set(
            LiveActivity(id: "plain", priority: .high, leading: AnyView(Color.clear), trailing: AnyView(Color.clear)), from: "timer"
        )
        #expect(center.stripHeight == 0)
        center.clear(id: "plain", from: "timer")
        #expect(center.stripHeight == 36)
    }
}
