import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// Which bubbles and list rows the notch draws for the live activities, and how they are named.
@Suite struct ActivitySlotsTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let crowded = NotchGeometry(screen: NotchGeometryTests.external, config: NotchBubbleGeometryTests.crowded)

    func makeCenter(_ count: Int, summaries: Bool = false) -> ActivityCenter {
        let center = ActivityCenter(scheduler: ManualScheduler())
        for index in 1...max(count, 1) where index <= count {
            center.set(
                LiveActivity(
                    id: "a\(index)", leading: AnyView(Color.clear), trailing: AnyView(Color.clear),
                    summary: summaries ? "Hoạt động \(index)" : nil
                ),
                from: "m"
            )
        }
        return center
    }

    /// The bubbles for what `center` shows now, the way the notch computes them.
    func bubbles(_ center: ActivityCenter, _ geometry: NotchGeometry? = nil) -> [ActivitySlot] {
        ActivitySlot.bubbles(of: center, capacity: (geometry ?? macBook).bubbleCapacity)
    }

    func shown(_ slots: [ActivitySlot]) -> [String] {
        slots.map {
            switch $0 {
            case .activity(let entry): entry.id
            case .overflow(let count): "+\(count)"
            }
        }
    }

    // MARK: Bubbles

    @Test func noActivityAndAPrimaryAloneHaveNoBubbles() {
        #expect(bubbles(makeCenter(0)).isEmpty)
        #expect(bubbles(makeCenter(1)).isEmpty)
    }

    @Test func oneAndTwoOtherActivitiesAreOneBubbleEach() {
        #expect(shown(bubbles(makeCenter(2))) == ["m/a2"])
        #expect(shown(bubbles(makeCenter(3))) == ["m/a2", "m/a3"])
    }

    @Test func moreThanThreeActivitiesEndTheRowWithAPlusNBubble() {
        // 4 in all: the primary, one bubble, and "+2" for the two that do not fit.
        #expect(shown(bubbles(makeCenter(4))) == ["m/a2", "+2"])
        #expect(shown(bubbles(makeCenter(5))) == ["m/a2", "+3"])
        // Past the cap Core keeps in `others` the count still adds up from `hiddenCount`.
        #expect(shown(bubbles(makeCenter(9))) == ["m/a2", "+7"])
    }

    @Test func theBubblesFollowCoreOrderNotInsertionOrder() {
        let center = makeCenter(2)
        center.set(LiveActivity(id: "alert", priority: .high, leading: AnyView(Color.clear), trailing: AnyView(Color.clear)), from: "m")
        #expect(center.current?.id == "m/alert")
        #expect(shown(bubbles(center)) == ["m/a1", "m/a2"])
    }

    @Test func aPanelThatHoldsOneBubbleShowsOneAndFoldsTheRestIntoIt() {
        #expect(crowded.bubbleCapacity == 1)
        #expect(shown(bubbles(makeCenter(2), crowded)) == ["m/a2"])
        #expect(shown(bubbles(makeCenter(3), crowded)) == ["+2"])
        #expect(shown(bubbles(makeCenter(5), crowded)) == ["+4"])
    }

    @Test func aPanelThatHoldsNoBubbleShowsNone() {
        #expect(ActivitySlot.bubbles(of: makeCenter(4), capacity: 0).isEmpty)
        #expect(ActivitySlot.bubbles(of: makeCenter(4), capacity: -1).isEmpty)
    }

    @Test func slotsHaveStableDistinctIDs() {
        let slots = bubbles(makeCenter(4))
        #expect(slots.map(\.id) == ["m/a2", "+more"])
        // The "+N" bubble is one view whose number changes, not a new bubble each time.
        #expect(bubbles(makeCenter(5)).map(\.id) == slots.map(\.id))
    }

    @Test func aBubbleSlotChangesWhenItsActivityIsUpdated() {
        let center = makeCenter(2)
        let before = bubbles(center)
        center.set(LiveActivity(id: "a2", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), summary: "new"), from: "m")
        #expect(bubbles(center) != before)
        #expect(bubbles(center).map(\.id) == before.map(\.id))
    }

    // MARK: List rows

    @Test func theListHasOneRowPerActivityPrimaryFirst() {
        let center = makeCenter(4)
        #expect(shown(ActivitySlot.listRows(of: center, capacity: NotchGeometry.maxListRows)) == ["m/a1", "m/a2", "m/a3", "m/a4"])
        #expect(shown(ActivitySlot.listRows(of: makeCenter(1), capacity: NotchGeometry.maxListRows)) == ["m/a1"])
        #expect(ActivitySlot.listRows(of: makeCenter(0), capacity: NotchGeometry.maxListRows).isEmpty)
    }

    @Test func aLongListEndsWithAPlusNRowInsteadOfGrowingForEver() {
        let cap = NotchGeometry.maxListRows
        #expect(ActivitySlot.listRows(of: makeCenter(cap), capacity: cap).count == cap)
        let long = shown(ActivitySlot.listRows(of: makeCenter(cap + 3), capacity: cap))
        #expect(long.count == cap)
        #expect(long.last == "+4")
        #expect(Array(long.dropLast()) == (1..<cap).map { "m/a\($0)" })
    }

    // MARK: What hangs off the collapsed notch

    @Test func accessoriesAreNothingWithoutAnActivityOrOutsideTheCollapsedNotch() {
        let center = makeCenter(3)
        #expect(CompactAccessories(activities: makeCenter(0), geometry: macBook, isListOpen: true, state: .compact) == .none)
        for state in [NotchState.closed, .open("a"), .open(nil), .toast] {
            #expect(CompactAccessories(activities: center, geometry: macBook, isListOpen: true, state: state) == .none, "\(state)")
        }
    }

    @Test func accessoryBubblesAreAtMostWhatFits() {
        #expect(CompactAccessories(activities: makeCenter(1), geometry: macBook, isListOpen: false, state: .compact).bubbles == 0)
        #expect(CompactAccessories(activities: makeCenter(2), geometry: macBook, isListOpen: false, state: .compact).bubbles == 1)
        #expect(CompactAccessories(activities: makeCenter(3), geometry: macBook, isListOpen: false, state: .compact).bubbles == 2)
        #expect(CompactAccessories(activities: makeCenter(8), geometry: macBook, isListOpen: false, state: .compact).bubbles == 2)
        #expect(CompactAccessories(activities: makeCenter(8), geometry: crowded, isListOpen: false, state: .compact).bubbles == 1)
        #expect(CompactAccessories.bubbleCount(activities: makeCenter(8), geometry: macBook) == 2)
    }

    @Test func theListHasARowForEveryActivityOnceItIsOpen() {
        #expect(CompactAccessories(activities: makeCenter(3), geometry: macBook, isListOpen: false, state: .compact).listRows == 0)
        #expect(CompactAccessories(activities: makeCenter(3), geometry: macBook, isListOpen: true, state: .compact).listRows == 3)
        #expect(CompactAccessories(activities: makeCenter(12), geometry: macBook, isListOpen: true, state: .compact).listRows == NotchGeometry.maxListRows)
        // Nothing to list beside the primary: no bubbles, so no list.
        #expect(CompactAccessories(activities: makeCenter(1), geometry: macBook, isListOpen: true, state: .compact).listRows == 0)
    }

    // MARK: Names

    @Test func anActivityIsNamedBySummaryThenModuleNameThenModuleID() {
        #expect(ActivityLabel.text(summary: "Đang phát", displayName: "Media", module: "media") == "Đang phát")
        #expect(ActivityLabel.text(summary: nil, displayName: "Media", module: "media") == "Media")
        // A module that is not registered (the debug publisher's) has no name: its id still says what it is.
        #expect(ActivityLabel.text(summary: nil, displayName: nil, module: "debug") == "debug")
        #expect(ActivityLabel.text(summary: "Thử nghiệm 1", displayName: nil, module: "debug") == "Thử nghiệm 1")
    }

    @Test func theOverflowBubbleAndRowAreNamedForVoiceOver() {
        #expect(ActivityLabel.overflow(count: 3) == "Còn 3 hoạt động khác")
    }
}
