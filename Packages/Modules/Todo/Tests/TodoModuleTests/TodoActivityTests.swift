import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import TodoModule

/// The optional "Còn 3 việc" on the collapsed notch.
@Suite struct TodoActivityTests {
    let f: ModuleFixture

    init() {
        f = ModuleFixture(ModuleFixture.aTypicalDay(fixedCalendar()))
    }

    func switchOn() async {
        f.settings.set(true, for: f.keys.showRemaining)
        await settle { f.activityEntry != nil }
    }

    @Test func isOffByDefault() async {
        await f.start()
        #expect(f.activityEntry == nil)
        #expect(f.module.publishedActivity == nil)
    }

    @Test func showsHowManyAreLeftWhenSwitchedOn() async throws {
        await f.start()
        await switchOn()
        let activity = try #require(f.activityEntry).activity
        #expect(activity.summary == "Còn 5 việc")
        #expect(f.module.publishedActivity == TodoActivityContent(remaining: 5, done: 1, total: 6))
        #expect(activity.minimal != nil)
        #expect(activity.bottom == nil)
    }

    @Test func isLowPriorityAndNeverAnExpiringNotice() async throws {
        await f.start()
        await switchOn()
        let activity = try #require(f.activityEntry).activity
        #expect(activity.priority == .low)
        #expect(activity.expiresAfter == nil)
    }

    @Test func musicKeepsTheSlot() async throws {
        await f.start()
        await switchOn()
        let music = LiveActivity(id: "nowPlaying", priority: .normal, leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()))
        f.harness.activities.set(music, from: "media")
        #expect(f.harness.activities.current?.module == "media")
        #expect(f.harness.activities.others.map(\.module) == ["todo"])
    }

    @Test func followsTheCount() async {
        await f.start()
        await switchOn()
        await f.module.complete("report")
        await settle { f.activityEntry?.activity.summary == "Còn 4 việc" }
        #expect(f.activityEntry?.activity.summary == "Còn 4 việc")
        await f.module.undo("report")
        await settle { f.activityEntry?.activity.summary == "Còn 5 việc" }
        #expect(f.activityEntry?.activity.summary == "Còn 5 việc")
    }

    @Test func singularCountReadsTheSame() async {
        await f.start()
        f.source.reminders = [todo("only", due: due(14))]
        await f.refreshed { f.source.emitChange() }
        await switchOn()
        #expect(f.activityEntry?.activity.summary == "Còn 1 việc")
    }

    @Test func goesWhenNothingIsLeft() async {
        await f.start()
        await switchOn()
        f.source.reminders = f.source.reminders.map {
            var reminder = $0
            reminder.isCompleted = true
            reminder.completionDate = f.calendar.on(14, at: 8)
            return reminder
        }
        await f.refreshed { f.source.emitChange() }
        #expect(f.activityEntry == nil)
        #expect(f.module.publishedActivity == nil)
    }

    @Test func goesWhenSwitchedOffAgain() async {
        await f.start()
        await switchOn()
        f.settings.set(false, for: f.keys.showRemaining)
        await settle { f.activityEntry == nil }
        #expect(f.activityEntry == nil)
    }

    @Test func isNotShownWithoutAccess() async {
        await f.start()
        await switchOn()
        f.harness.permissions.statuses[.reminders] = .denied
        await f.refreshed { f.module.tabAppeared() }
        #expect(f.activityEntry == nil)
    }

    @Test func switchingItOnDoesNotReadRemindersAgain() async {
        await f.start()
        let fetches = f.source.fetchCount
        await switchOn()
        #expect(f.source.fetchCount == fetches)
    }

    @Test func aChangeThatLeavesTheCountAlonePublishesNothingNew() async throws {
        await f.start()
        await switchOn()
        let before = try #require(f.activityEntry)
        f.source.reminders += [todo("later2", due: due(21))]
        await f.refreshed { f.source.emitChange() }
        #expect(f.activityEntry == before)
    }

    @Test func theRingShowsHowMuchIsDone() {
        #expect(TodoActivityContent(remaining: 5, done: 1, total: 6).fraction == 1.0 / 6.0)
        #expect(TodoActivityContent(remaining: 2, done: 0, total: 2).fraction == 0)
        #expect(TodoActivityContent(remaining: 1, done: 3, total: 4).fraction == 0.75)
    }
}
