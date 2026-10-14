import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import CalendarModule

@Suite struct CalendarModuleTests {
    let calendar: Calendar
    let source = FakeCalendarDataSource()
    let clock: TestClock
    let opener = RecordingOpener()
    let dayCenter = NotificationCenter()
    let wakeCenter = NotificationCenter()
    let module: CalendarModule
    let harness: RegistryHarness

    /// Wednesday 14 October 2026, 09:00, in Ho Chi Minh City.
    init() {
        let calendar = fixedCalendar()
        let clock = TestClock(calendar.on(14, at: 9))
        let opener = self.opener
        self.calendar = calendar
        self.clock = clock
        module = CalendarModule(
            dataSource: source, now: { clock.now }, calendar: calendar, openURL: { opener.open($0) },
            dayChangeCenter: dayCenter, wakeCenter: wakeCenter
        )
        harness = RegistryHarness([module])
        harness.permissions.statuses[.calendars] = .granted
    }

    var keys: CalendarSettingsKeys { CalendarSettingsKeys(harness.settingsEnvironment(for: "calendar")!.settings) }
    var meetingEntry: ActivityCenter.Entry? { harness.activities.entries.first { $0.id == "calendar/meeting" } }

    /// Starts the module and waits for its first agenda.
    func start() async {
        await harness.registry.bootstrap()
        await settle { module.appliedRefreshes >= 1 }
    }

    /// Moves the clock and lets the one-minute timer run, as a minute passing would.
    func tick(to now: Date) async {
        clock.now = now
        let applied = module.appliedRefreshes
        harness.scheduler.advance(by: module.minuteTimerDelay)
        await settle { module.appliedRefreshes > applied }
    }

    /// Runs `trigger`, then waits until the module has seen it and queued a refresh.
    func trigger(_ action: () -> Void) async {
        let before = module.refreshRequests
        action()
        await settle { module.refreshRequests > before }
    }

    func standup(at hour: Int = 10, _ minute: Int = 0) -> AgendaEvent {
        event("standup", calendar.on(14, at: hour, minute), calendar.on(14, at: hour + 1, minute))
    }

    // MARK: Module basics

    @Test func descriptor() {
        let descriptor = module.descriptor
        #expect(descriptor.id == "calendar")
        #expect(descriptor.displayName == "Lịch")
        #expect(descriptor.systemImage == "calendar")
        #expect(descriptor.order == 600)
    }

    @Test func declaresThePermissionsItUsesAndWhy() {
        let descriptor = module.descriptor
        #expect(descriptor.permissions == [.calendars])
        #expect(descriptor.optionalPermissions == [.reminders])
        #expect(descriptor.permissionReasons == [
            .calendars: "Hiện sự kiện sắp tới và thông báo họp.",
            .reminders: "Hiện lời nhắc khi bật “Hiện lời nhắc đến hạn hôm nay”.",
        ])
    }

    @Test func waitsForCalendarsAccess() async {
        harness.permissions.statuses[.calendars] = .notDetermined
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "calendar") == .needsPermission(.calendars))
        #expect(source.eventFetchCount == 0)
        #expect(harness.registry.tabs.isEmpty)
    }

    @Test func startsOnceCalendarsAccessIsGranted() async {
        source.events = [standup()]
        harness.permissions.statuses[.calendars] = .notDetermined
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "calendar") == .needsPermission(.calendars))

        // The user grants it in System Settings; the app notices on its next poll and starts the module.
        harness.permissions.statuses[.calendars] = .granted
        await harness.registry.refreshPermissions()
        await settle { module.appliedRefreshes >= 1 }

        #expect(harness.registry.state(of: "calendar") == .running)
        #expect(module.state.agenda.today.map(\.id) == ["standup"])
    }

    @Test func tab() async throws {
        await start()
        #expect(harness.registry.state(of: "calendar") == .running)
        let tab = try #require(harness.registry.tabs.first)
        #expect(tab.id == "calendar")
        #expect(tab.title == "Lịch")
        #expect(tab.systemImage == "calendar")
        #expect(tab.preferredHeight == 220)
        #expect(!tab.acceptsKeyboard)
    }

    @Test func startReadsTheWeekAheadAndBuildsTheAgenda() async {
        source.events = [
            allDayEvent("holiday", on: 14, in: calendar),
            event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11)),
            event("tomorrow", calendar.on(15, at: 9), calendar.on(15, at: 10)),
        ]
        await start()

        #expect(source.eventRanges == [AgendaBuilder.fetchRange(now: clock.now, calendar: calendar)])
        #expect(module.state.agenda.today.map(\.id) == ["holiday", "standup"])
        #expect(module.state.agenda.next?.id == "standup")
        #expect(module.state.now == clock.now)
    }

    @Test func stoppingClearsEverything() async {
        source.events = [standup(at: 9, 3)]
        clock.now = calendar.on(14, at: 9)
        await start()
        #expect(meetingEntry != nil)

        await harness.registry.setEnabled(false, for: "calendar")

        #expect(harness.activities.entries.isEmpty)
        #expect(module.state.agenda == Agenda())
        #expect(harness.registry.tabs.isEmpty)
    }

    // MARK: Refresh triggers

    /// The data source already waits for its changes to settle, so the module doesn't wait a second time.
    @Test func aChangeRefreshesAtOnce() async {
        await start()
        source.events = [standup()]

        await trigger { source.emitChange() }
        await settle { module.appliedRefreshes == 2 }

        #expect(module.state.agenda.today.map(\.id) == ["standup"])
        // Only the minute timer is waiting: no debounce was scheduled.
        #expect(harness.scheduler.pendingCount == 1)
    }

    @Test func aBurstOfWakesIsOneRefresh() async {
        await start()
        for _ in 0..<5 {
            await trigger { wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil) }
            harness.scheduler.advance(by: .milliseconds(400))
        }
        #expect(module.appliedRefreshes == 1)

        harness.scheduler.advance(by: .seconds(1))
        await settle { module.appliedRefreshes == 2 }
        await letAnythingPending()
        #expect(module.appliedRefreshes == 2)
        #expect(source.eventFetchCount == 2)
    }

    @Test func aNewDayRefreshes() async {
        await start()
        source.events = [event("tomorrow", calendar.on(15, at: 9), calendar.on(15, at: 10))]
        clock.now = calendar.on(15, at: 0, 0, 1)

        await trigger { dayCenter.post(name: .NSCalendarDayChanged, object: nil) }
        harness.scheduler.advance(by: .seconds(1))
        await settle { module.appliedRefreshes == 2 }

        #expect(module.state.agenda.today.map(\.id) == ["tomorrow"])
        #expect(source.eventRanges.last == AgendaBuilder.fetchRange(now: calendar.on(15, at: 0, 0, 1), calendar: calendar))
    }

    @Test func wakingTheMacRefreshes() async {
        await start()
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 30)

        await trigger { wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil) }
        harness.scheduler.advance(by: .seconds(1))
        await settle { module.appliedRefreshes == 2 }

        #expect(module.state.now == calendar.on(14, at: 9, 30))
        #expect(module.state.agenda.today.map(\.id) == ["standup"])
    }

    /// The timer waits for the next minute boundary plus a short margin, so the countdown changes as the minute does.
    @Test func refreshesOnTheMinuteBoundary() async {
        clock.now = calendar.on(14, at: 9, 0, 30)
        await start()
        harness.scheduler.advance(by: .milliseconds(30_099))
        await letAnythingPending()
        #expect(module.appliedRefreshes == 1)

        clock.now = calendar.on(14, at: 9, 1).addingTimeInterval(0.1)
        harness.scheduler.advance(by: .milliseconds(1))
        await settle { module.appliedRefreshes == 2 }

        // Fired right on time, the next one is a full minute away.
        harness.scheduler.advance(by: .milliseconds(59_999))
        await letAnythingPending()
        #expect(module.appliedRefreshes == 2)
        harness.scheduler.advance(by: .milliseconds(1))
        await settle { module.appliedRefreshes == 3 }
        #expect(source.eventFetchCount == 3)
    }

    @Test func aTimerThatFiresLateAimsForTheNextBoundary() async {
        await start()
        // Fires 20 s late, at 9:01:20: the next boundary is 40 s away.
        clock.now = calendar.on(14, at: 9, 1, 20)
        harness.scheduler.advance(by: module.minuteTimerDelay)
        await settle { module.appliedRefreshes == 2 }

        #expect(module.minuteTimerDelay == .milliseconds(40_100))
    }

    @Test func aStoppedModuleIgnoresEveryTrigger() async {
        await start()
        await harness.registry.setEnabled(false, for: "calendar")
        let fetches = source.eventFetchCount
        let requests = module.refreshRequests

        source.emitChange()
        dayCenter.post(name: .NSCalendarDayChanged, object: nil)
        wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        harness.scheduler.advance(by: .seconds(600))
        await letAnythingPending()

        #expect(source.eventFetchCount == fetches)
        #expect(harness.scheduler.pendingCount == 0)
        #expect(module.refreshRequests == requests)
    }

    @Test func restartingStartsFresh() async {
        source.events = [standup(at: 9, 3)]
        await start()
        module.dismissMeeting(module.state.featured!)
        #expect(meetingEntry == nil)

        await harness.registry.setEnabled(false, for: "calendar")
        await harness.registry.setEnabled(true, for: "calendar")
        await settle { module.appliedRefreshes >= 1 && meetingEntry != nil }

        #expect(meetingEntry != nil)
    }

    // MARK: Meeting activity

    @Test func theActivityAppearsFiveMinutesBeforeTheStart() async {
        source.events = [standup()]
        await start()
        #expect(meetingEntry == nil)

        await tick(to: calendar.on(14, at: 9, 54, 59))
        #expect(meetingEntry == nil)

        await tick(to: calendar.on(14, at: 9, 55))
        #expect(meetingEntry != nil)
        #expect(meetingEntry?.activity.priority == .normal)
        #expect(module.publishedMeeting?.state == .upcoming(minutesLeft: 5))
        #expect(module.publishedMeeting?.countdown == "5 phút")
    }

    @Test func theCountdownUpdatesInPlaceOncePerMinute() async {
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 55)
        await start()
        let first = meetingEntry
        #expect(first != nil)

        // A refresh inside the same minute changes nothing, so the entry is not touched.
        clock.now = calendar.on(14, at: 9, 55, 30)
        await trigger { source.emitChange() }
        await settle { module.appliedRefreshes == 2 }
        #expect(meetingEntry == first)

        await tick(to: calendar.on(14, at: 9, 56, 30))
        #expect(harness.activities.entries.map(\.id) == ["calendar/meeting"])
        #expect(meetingEntry != first)
        #expect(module.publishedMeeting?.countdown == "4 phút")

        let fourMinutes = meetingEntry
        await trigger { source.emitChange() }
        await settle { module.appliedRefreshes == 4 }
        #expect(meetingEntry == fourMinutes)
    }

    @Test func thePriorityRisesToHighWithinAMinuteOfTheStart() async {
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 55)
        await start()
        #expect(meetingEntry?.activity.priority == .normal)

        await tick(to: calendar.on(14, at: 9, 58))
        #expect(meetingEntry?.activity.priority == .normal)

        await tick(to: calendar.on(14, at: 9, 59))
        #expect(meetingEntry?.activity.priority == .high)
        #expect(module.publishedMeeting?.countdown == "1 phút")

        await tick(to: calendar.on(14, at: 10, 0, 20))
        #expect(meetingEntry?.activity.priority == .high)
        #expect(module.publishedMeeting?.countdown == "Đang diễn ra")

        await tick(to: calendar.on(14, at: 10, 2))
        #expect(meetingEntry?.activity.priority == .normal)
        #expect(module.publishedMeeting?.countdown == "Đang diễn ra")
    }

    @Test func theActivityHidesFiveMinutesAfterTheStart() async {
        source.events = [standup()]
        clock.now = calendar.on(14, at: 10, 4, 59)
        await start()
        #expect(meetingEntry != nil)

        await tick(to: calendar.on(14, at: 10, 5))
        #expect(meetingEntry == nil)
        #expect(module.publishedMeeting == nil)
    }

    @Test func leadMinutesComeFromSettings() async {
        source.events = [standup()]
        harness.settings.set(10, for: keys.meetingLeadMinutes)
        clock.now = calendar.on(14, at: 9, 50)
        await start()
        #expect(meetingEntry != nil)
        #expect(module.publishedMeeting?.state == .upcoming(minutesLeft: 10))

        await tick(to: calendar.on(14, at: 9, 49))
        #expect(meetingEntry == nil)
    }

    @Test func changingTheLeadAppliesAtOnce() async {
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 50)
        await start()
        #expect(meetingEntry == nil)

        harness.settings.set(15, for: keys.meetingLeadMinutes)
        await settle { meetingEntry != nil }
        #expect(module.publishedMeeting?.state == .upcoming(minutesLeft: 10))
    }

    @Test func leadMinutesStayWithinOneAndThirty() {
        let settings = harness.settingsEnvironment(for: "calendar")!.settings
        #expect(settings.value(keys.meetingLeadMinutes) == 5)
        settings.set(0, for: keys.meetingLeadMinutes)
        #expect(settings.value(keys.meetingLeadMinutes) == 1)
        settings.set(90, for: keys.meetingLeadMinutes)
        #expect(settings.value(keys.meetingLeadMinutes) == 30)
    }

    @Test func dismissingHidesTheActivityForGood() async {
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 56)
        await start()
        let meeting = module.state.featured!
        #expect(module.state.canDismissFeatured)

        module.dismissMeeting(meeting)
        #expect(meetingEntry == nil)
        #expect(!module.state.canDismissFeatured)

        await tick(to: calendar.on(14, at: 9, 59))
        #expect(meetingEntry == nil)
        await tick(to: calendar.on(14, at: 10, 1))
        #expect(meetingEntry == nil)
    }

    @Test func aMovedMeetingShowsAgain() async {
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 56)
        await start()
        module.dismissMeeting(module.state.featured!)
        #expect(meetingEntry == nil)

        // Rescheduled to 10:30: another occurrence, so another id.
        source.events = [event("standup@moved", calendar.on(14, at: 10, 30), calendar.on(14, at: 11))]
        await tick(to: calendar.on(14, at: 10, 26))
        #expect(meetingEntry != nil)
    }

    @Test func joiningOpensTheLinkAndDismisses() async {
        let link = URL(string: "https://meet.google.com/abc-defg-hij")!
        source.events = [event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11), meetingURL: link)]
        clock.now = calendar.on(14, at: 9, 57)
        await start()
        #expect(meetingEntry != nil)

        module.join(module.state.featured!)

        #expect(opener.urls == [link])
        #expect(meetingEntry == nil)
    }

    @Test func joiningAnEventWithoutALinkOpensNothing() async {
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 57)
        await start()
        module.join(module.state.featured!)
        #expect(opener.urls.isEmpty)
    }

    @Test func aRunningLongEventDoesNotHideALaterMeeting() async {
        source.events = [
            event("workshop", calendar.on(14, at: 9), calendar.on(14, at: 17)),
            event("review", calendar.on(14, at: 14), calendar.on(14, at: 15)),
        ]
        clock.now = calendar.on(14, at: 13, 56)
        await start()

        #expect(module.state.agenda.next?.id == "workshop")
        #expect(meetingEntry != nil)
        #expect(module.publishedMeeting?.eventID == "review")
        #expect(module.state.featured?.id == "review")
    }

    @Test func aMeetingAfterMidnightShowsWithinTheLead() async {
        let settings = harness.settingsEnvironment(for: "calendar")!.settings
        settings.set(30, for: keys.meetingLeadMinutes)
        source.events = [event("early", calendar.on(15, at: 0, 10), calendar.on(15, at: 0, 40))]
        clock.now = calendar.on(14, at: 23, 39)
        await start()
        #expect(meetingEntry == nil)

        await tick(to: calendar.on(14, at: 23, 40))

        #expect(meetingEntry != nil)
        #expect(module.publishedMeeting?.eventID == "early")
        #expect(module.publishedMeeting?.state == .upcoming(minutesLeft: 30))
        #expect(module.state.featured?.id == "early")
        #expect(module.state.canDismissFeatured)
    }

    @Test func theFeaturedEventFallsBackToTheNextOne() async {
        source.events = [
            event("workshop", calendar.on(14, at: 9), calendar.on(14, at: 17)),
            event("tomorrow", calendar.on(15, at: 9), calendar.on(15, at: 10)),
        ]
        clock.now = calendar.on(14, at: 11)
        await start()
        // Nothing starts later today, so the running workshop is what's next.
        #expect(module.state.featured?.id == "workshop")
        #expect(meetingEntry == nil)
        #expect(!module.state.canDismissFeatured)
    }

    @Test func theFeaturedEventStaysUntilItStartsTheNextDay() async {
        source.events = [event("tomorrow", calendar.on(15, at: 9), calendar.on(15, at: 10))]
        await start()
        #expect(module.state.featured?.id == "tomorrow")
        #expect(meetingEntry == nil)
    }

    // MARK: Filters

    @Test func hiddenCalendarsAreFiltered() async {
        source.events = [
            event("work standup", calendar.on(14, at: 10), calendar.on(14, at: 11), calendarID: "work"),
            event("dentist", calendar.on(14, at: 12), calendar.on(14, at: 13), calendarID: "personal"),
        ]
        harness.settings.set(["personal"], for: keys.hiddenCalendarIDs)
        await start()
        #expect(module.state.agenda.today.map(\.id) == ["work standup"])
        #expect(module.state.agenda.next?.id == "work standup")
    }

    @Test func hiddenCalendarsNeverFeedTheActivity() async {
        source.events = [event("dentist", calendar.on(14, at: 10), calendar.on(14, at: 11), calendarID: "personal")]
        harness.settings.set(["personal"], for: keys.hiddenCalendarIDs)
        clock.now = calendar.on(14, at: 9, 57)
        await start()
        #expect(meetingEntry == nil)
    }

    @Test func changingTheHiddenCalendarsRefreshes() async {
        source.events = [
            event("work standup", calendar.on(14, at: 10), calendar.on(14, at: 11), calendarID: "work"),
            event("dentist", calendar.on(14, at: 12), calendar.on(14, at: 13), calendarID: "personal"),
        ]
        await start()
        #expect(module.state.agenda.today.count == 2)

        harness.settings.set(["personal"], for: keys.hiddenCalendarIDs)
        await settle { module.state.agenda.today.count == 1 }
        #expect(module.state.agenda.today.map(\.id) == ["work standup"])

        harness.settings.set([], for: keys.hiddenCalendarIDs)
        await settle { module.state.agenda.today.count == 2 }
        #expect(module.state.agenda.today.count == 2)
    }

    @Test func allDayEventsCanBeLeftOut() async {
        source.events = [allDayEvent("holiday", on: 14, in: calendar), standup()]
        await start()
        #expect(module.state.agenda.today.map(\.id) == ["holiday", "standup"])

        harness.settings.set(false, for: keys.showAllDay)
        await settle { module.state.agenda.today.count == 1 }
        #expect(module.state.agenda.today.map(\.id) == ["standup"])
    }

    @Test func settingsDefaults() {
        let settings = harness.settingsEnvironment(for: "calendar")!.settings
        #expect(!settings.value(keys.showReminders))
        #expect(settings.value(keys.meetingLeadMinutes) == 5)
        #expect(settings.value(keys.hiddenCalendarIDs).isEmpty)
        #expect(settings.value(keys.showAllDay))
    }

    @Test func settingsKeysLiveUnderTheModuleNamespace() {
        #expect(keys.showReminders.name == "module.calendar.showReminders")
        #expect(keys.meetingLeadMinutes.name == "module.calendar.meetingLeadMinutes")
        #expect(keys.hiddenCalendarIDs.name == "module.calendar.hiddenCalendarIDs")
        #expect(keys.showAllDay.name == "module.calendar.showAllDay")
    }

    @Test func settingsRowsExistWhetherOrNotTheModuleRuns() {
        #expect(harness.registry.settingsView(for: "calendar") != nil)
    }

    // MARK: Reminders

    @Test func remindersStayOffByDefault() async {
        harness.permissions.statuses[.reminders] = .granted
        source.reminders = [reminder("r1")]
        await start()
        #expect(module.state.reminders == .hidden)
        #expect(source.reminderFetchCount == 0)
    }

    @Test func remindersShowWhenEnabledAndGranted() async {
        harness.permissions.statuses[.reminders] = .granted
        harness.settings.set(true, for: keys.showReminders)
        source.reminders = [
            reminder("later", due: DateComponents(year: 2026, month: 10, day: 14, hour: 17)),
            reminder("overdue", due: DateComponents(year: 2026, month: 10, day: 13), overdue: true),
        ]
        await start()
        #expect(module.state.reminders == .items([source.reminders[1], source.reminders[0]]))
        #expect(source.reminderFetchCount == 1)
    }

    @Test func remindersAskForAccessWhenEnabledWithoutIt() async {
        harness.permissions.statuses[.reminders] = .notDetermined
        harness.settings.set(true, for: keys.showReminders)
        source.reminders = [reminder("r1")]
        await start()
        #expect(module.state.reminders == .needsAccess)
        #expect(source.reminderFetchCount == 0)
        #expect(harness.permissions.requested.isEmpty)
    }

    @Test func turningRemindersOnShowsThemWhenGranted() async {
        harness.permissions.statuses[.reminders] = .granted
        source.reminders = [reminder("r1")]
        await start()
        #expect(module.state.reminders == .hidden)

        harness.settings.set(true, for: keys.showReminders)
        await settle { module.state.reminders != .hidden }
        #expect(module.state.reminders == .items([reminder("r1")]))

        harness.settings.set(false, for: keys.showReminders)
        await settle { module.state.reminders == .hidden }
        #expect(module.state.reminders == .hidden)
    }

    @Test func requestingAccessFromTheTabRefreshes() async {
        harness.permissions.statuses[.reminders] = .notDetermined
        harness.settings.set(true, for: keys.showReminders)
        source.reminders = [reminder("r1")]
        await start()
        #expect(module.state.reminders == .needsAccess)

        await module.requestRemindersAccess()

        #expect(harness.permissions.requested == [.reminders])
        #expect(module.state.reminders == .items([reminder("r1")]))
    }

    @Test func aDeniedRequestStaysOnTheButtonAndOpensSystemSettings() async {
        harness.permissions.statuses[.reminders] = .denied
        harness.permissions.requestResult = .denied
        harness.settings.set(true, for: keys.showReminders)
        await start()

        await module.requestRemindersAccess()

        #expect(module.state.reminders == .needsAccess)
        #expect(harness.permissions.openedSettings == [.reminders])
    }

    @Test func aGrantFromElsewhereShowsWhenTheTabAppears() async {
        harness.permissions.statuses[.reminders] = .notDetermined
        harness.settings.set(true, for: keys.showReminders)
        source.reminders = [reminder("r1")]
        await start()
        #expect(module.state.reminders == .needsAccess)

        // The registry's Settings button, or System Settings itself: the module hears nothing.
        await harness.registry.grant(.reminders)
        module.tabAppeared()
        await settle { module.state.reminders != .needsAccess }

        #expect(module.state.reminders == .items([reminder("r1")]))
    }

    @Test func openingTheTabWithoutAChangeDoesNotRefresh() async {
        harness.permissions.statuses[.reminders] = .granted
        harness.settings.set(true, for: keys.showReminders)
        await start()
        module.tabAppeared()
        await letAnythingPending()
        #expect(module.appliedRefreshes == 1)
    }

    @Test func aGrantFromElsewhereShowsAtTheNextMinute() async {
        harness.permissions.statuses[.reminders] = .notDetermined
        harness.settings.set(true, for: keys.showReminders)
        source.reminders = [reminder("r1")]
        await start()

        harness.permissions.statuses[.reminders] = .granted
        await tick(to: calendar.on(14, at: 9, 1))

        #expect(module.state.reminders == .items([reminder("r1")]))
    }

    @Test func completingAReminderCallsTheDataSource() async {
        harness.permissions.statuses[.reminders] = .granted
        harness.settings.set(true, for: keys.showReminders)
        source.reminders = [reminder("r1"), reminder("r2")]
        await start()

        await module.complete(reminder("r1"))

        #expect(source.completedIDs == ["r1"])
        #expect(module.state.reminders == .items([reminder("r2")]))
    }

    @Test func aReminderDisappearsAtOnceWhileItIsBeingCompleted() async {
        harness.permissions.statuses[.reminders] = .granted
        harness.settings.set(true, for: keys.showReminders)
        source.reminders = [reminder("r1"), reminder("r2")]
        await start()

        module.hideCompleting(reminder("r1"))

        #expect(module.state.reminders == .items([reminder("r2")]))
    }

    @Test func aReminderThatCouldNotBeCompletedComesBack() async {
        harness.permissions.statuses[.reminders] = .granted
        harness.settings.set(true, for: keys.showReminders)
        source.reminders = [reminder("r1")]
        source.completionFailure = CalendarServiceError.reminderNotFound
        await start()

        await module.complete(reminder("r1"))

        #expect(source.completedIDs.isEmpty)
        #expect(module.state.reminders == .items([reminder("r1")]))
    }

    // MARK: Opening events

    @Test func theTabsButtonsReachTheModule() async {
        let link = URL(string: "https://zoom.us/j/123456789")!
        source.events = [event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11), meetingURL: link)]
        clock.now = calendar.on(14, at: 9, 57)
        await start()
        let meeting = module.state.featured!
        let actions = module.actions

        actions.open(meeting)
        #expect(opener.urls.map(\.absoluteString) == ["ical://ekevent/standup"])
        actions.dismiss(meeting)
        #expect(meetingEntry == nil)
        actions.join(meeting)
        #expect(opener.urls.last == link)
    }

    @Test func clickingAnEventOpensItInCalendar() async {
        await start()
        module.open(event("ABC-123", calendar.on(14, at: 10), calendar.on(14, at: 11)))
        #expect(opener.urls.map(\.absoluteString) == ["ical://ekevent/ABC-123"])
    }

    @Test func anEventThatCannotBeOpenedOpensCalendarInstead() async {
        opener.unsupportedSchemes = ["ical"]
        await start()
        module.open(event("ABC-123", calendar.on(14, at: 10), calendar.on(14, at: 11)))
        #expect(opener.urls.map(\.absoluteString) == ["ical://ekevent/ABC-123", "file:///System/Applications/Calendar.app"])
    }

    @Test func aRecurringEventOpensByItsItemIdentifier() async {
        await start()
        var occurrence = event("ABC-123@1792000000", calendar.on(14, at: 10), calendar.on(14, at: 11))
        occurrence.calendarItemIdentifier = "ABC-123"
        module.open(occurrence)
        #expect(opener.urls.map(\.absoluteString) == ["ical://ekevent/ABC-123"])
    }
}
