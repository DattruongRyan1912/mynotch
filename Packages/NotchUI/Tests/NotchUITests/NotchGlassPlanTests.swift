import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// What glass the notch asks for, as a value: whether the notch and its bubbles share a container, and for each shape its
/// name in the morph namespace and its `Glass`. The root view and the bubbles draw from this plan, so what is read here is
/// what is drawn.
@Suite struct NotchGlassPlanTests {
    let accent = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.9)
    let glass = NotchSurface.liquidGlass(tinted: false)
    let tinted = NotchSurface.liquidGlass(tinted: true)
    let allStates: [NotchState] = [.closed, .compact, .open(nil), .open("a"), .toast]

    func plan(_ surface: NotchSurface, bubbles: [String] = []) -> NotchGlassPlan {
        NotchGlassPlan(surface: surface, bubbleIDs: bubbles, accent: accent)
    }

    // MARK: the classic look draws no glass

    @Test func theBlackAndTheBlurAskForNoContainerAndNoShape() {
        for surface in [NotchSurface.solid, .material] {
            let plan = plan(surface, bubbles: ["a", "b"])
            #expect(!plan.usesContainer, "\(surface)")
            #expect(plan.containerSpacing == nil)
            #expect(plan.notch == nil)
            #expect(plan.bubbles.isEmpty)
            #expect(plan.shapes.isEmpty)
            #expect(plan == .none)
        }
    }

    // MARK: one family

    @Test func glassIsOneContainerWithTheNotchAndEachBubbleInIt() {
        let plan = plan(glass, bubbles: ["a", "b"])
        #expect(plan.usesContainer)
        #expect(plan.containerSpacing == NotchGlassPlan.containerSpacing)
        #expect(plan.notch?.id == .notch)
        #expect(plan.bubbles.map(\.id) == [.bubble("a"), .bubble("b")])
        #expect(plan.shapes.count == 3)
        #expect(plan.shapes.first?.id == .notch, "the notch first, then the bubbles in order")
    }

    @Test func noBubbleSharesAnIdentityWithTheNotchOrWithAnotherBubble() {
        let ids = plan(glass, bubbles: ["a", "b", "c"]).shapes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func aBubbleIsFoundByItsActivityID() {
        let plan = plan(glass, bubbles: ["a", "b"])
        #expect(plan.bubble(id: "b")?.id == .bubble("b"))
        #expect(plan.bubble(id: "nope") == nil)
        #expect(NotchGlassPlan.none.bubble(id: "a") == nil)
    }

    @Test func aBubbleIsNamedAfterItsActivityAndKeepsItsNameWhateverElseChanges() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        for index in 1...4 {
            center.set(
                LiveActivity(id: "a\(index)", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "Hoạt động \(index)"),
                from: "m"
            )
        }
        let slots = ActivitySlot.bubbles(of: center, capacity: 3)
        let ids = slots.map(\.id)
        let plan = plan(glass, bubbles: ids)
        // What a bubble does: look its own shape up by its slot's id.
        for slot in slots {
            #expect(plan.bubble(id: slot.id)?.id == .bubble(slot.id))
        }
        #expect(plan.bubbles.map(\.id) == ids.map { .bubble($0) })
        #expect(!plan.bubbles.map(\.id).contains(.notch))
        // Asked again, and in the reverse order, the same names: a bubble that moves keeps its glass.
        #expect(self.plan(glass, bubbles: ids.reversed()).bubbles.map(\.id) == ids.reversed().map { .bubble($0) })
        #expect(self.plan(glass, bubbles: ids.reversed()).bubble(id: ids[0]) == plan.bubble(id: ids[0]))
    }

    @Test func thePlusNBubbleKeepsItsNameWhileItsNumberChanges() {
        #expect(ActivitySlot.overflow(3).id == ActivitySlot.overflow(4).id)
        let before = plan(glass, bubbles: [ActivitySlot.overflow(3).id])
        let after = plan(glass, bubbles: [ActivitySlot.overflow(4).id])
        #expect(before == after)
        #expect(before.bubbles.first?.id != .notch)
    }

    // MARK: the notch's glass is the same in every state

    @Test func theNotchHasTheSamePlanInEveryStateSoOpeningAndClosingMorphsOneShapeWithoutChangingIt() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        let theme = NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        let plans = allStates.map { NotchGlassPlan(surface: theme.surface(for: $0), bubbleIDs: [], accent: accent) }
        #expect(plans.allSatisfy { $0 == plans[0] }, "the shape, its name and its Glass do not depend on the state")
        #expect(plans[0].notch?.id == .notch)
    }

    @Test func theNotchGlassIsNeverInteractive() {
        #expect(plan(glass).notch?.glass == Glass.regular)
        #expect(plan(tinted).notch?.glass == Glass.regular.tint(accent.opacity(NotchTokens.glassTintOpacity)))
        #expect(plan(glass).notch?.glass != Glass.regular.interactive())
        #expect(plan(tinted).notch?.glass != Glass.regular.tint(accent.opacity(NotchTokens.glassTintOpacity)).interactive())
    }

    // MARK: bubbles are buttons

    @Test func aBubbleIsInteractiveGlassBecauseItIsAButton() {
        let plan = plan(glass, bubbles: ["a", "b"])
        #expect(plan.bubbles.allSatisfy { $0.glass == Glass.regular.interactive() })
        #expect(plan.bubbles.allSatisfy { $0.glass != Glass.regular })
    }

    // MARK: tint

    @Test func theTintIsInTheNotchAndInTheBubblesOnlyWhenAsked() {
        let hint = accent.opacity(NotchTokens.glassTintOpacity)
        let on = plan(tinted, bubbles: ["a"])
        #expect(on.notch?.glass == Glass.regular.tint(hint))
        #expect(on.bubbles.first?.glass == Glass.regular.tint(hint).interactive())
        let off = plan(glass, bubbles: ["a"])
        #expect(off.notch?.glass == Glass.regular)
        #expect(off.bubbles.first?.glass == Glass.regular.interactive())
        #expect(NotchTokens.glassTintOpacity > 0 && NotchTokens.glassTintOpacity <= 0.3, "a hint of the accent, not a coat of it")
    }

    @Test func theTintFollowsTheAccentItIsGiven() {
        let other = Color(.sRGB, red: 0.9, green: 0.1, blue: 0.1)
        let first = NotchGlassPlan(surface: tinted, bubbleIDs: [], accent: accent)
        let second = NotchGlassPlan(surface: tinted, bubbleIDs: [], accent: other)
        #expect(first != second)
        #expect(second.notch?.glass == Glass.regular.tint(other.opacity(NotchTokens.glassTintOpacity)))
    }

    // MARK: the container's spacing

    @Test func shapesBlendOnlyWhileTheyMoveNeverAtRest() {
        let spacing = NotchGlassPlan.containerSpacing
        #expect(spacing > 0)
        #expect(spacing < NotchGeometry.bubbleGap, "a bubble at rest is further from its neighbour than that")
        // The nearest the notch comes to its first bubble at rest is its top ear's tip, which reaches the width of the
        // shape's frame; the bubble is a circle, so the distance from the tip to it is that to its centre less its radius.
        for screen in [NotchGeometryTests.macBook14, NotchGeometryTests.external] {
            let geometry = NotchGeometry(screen: screen, config: NotchLayoutConfig())
            let bubble = geometry.bubbleFrame(at: 0)
            let tip = CGPoint(x: geometry.shapeSize(for: .compact).width / 2, y: 0)
            let distance = hypot(tip.x - bubble.midX, tip.y - bubble.midY) - bubble.width / 2
            #expect(spacing < distance, "the ear's tip is \(distance) from the bubble")
        }
    }
}
