import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import CalendarModule

/// "Báo lại" and "Bỏ qua" through the module: the card hides, comes back when it should, and the answers outlive a restart.
@Suite struct MeetingAnswersTests {
    let calendar: Calendar
    let source = FakeCalendarDataSource()
    let clock: TestClock
    let opener = RecordingOpener()
    let module: CalendarModule
    let harness: RegistryHarness

    /// Wednesday 14 October 2026, 09:46, in Ho Chi Minh City, with a lead of 15 minutes so the card is on show.
    init() {
        let calendar = fixedCalendar()
        let clock = TestClock(calendar.on(14, at: 9, 46))
        let opener = self.opener
        self.calendar = calendar
        self.clock = clock
        module = CalendarModule(
            dataSource: source, now: { clock.now }, calendar: calendar, openURL: { opener.open($0) },
            dayChangeCenter: NotificationCenter(), wakeCenter: NotificationCenter()
        )
        harness = RegistryHarness([module])
        harness.permissions.statuses[.calendars] = .granted
        harness.settings.set(15, for: keys.meetingLeadMinutes)
    }

    var keys: CalendarSettingsKeys { CalendarSettingsKeys(harness.settingsEnvironment(for: "calendar")!.settings) }
    var meetingEntry: ActivityCenter.Entry? { harness.activities.entries.first { $0.id == "calendar/meeting" } }
    var stored: MeetingReplies { harness.settings.value(keys.meetingReplies) }

    func standup(id: String = "standup", at hour: Int = 10, _ minute: Int = 0) -> AgendaEvent {
        event(id, calendar.on(14, at: hour, minute), calendar.on(14, at: hour + 1, minute))
    }

    func start() async {
        await harness.registry.bootstrap()
        await settle { module.appliedRefreshes >= 1 }
    }

    /// Stops the module and starts it again, as quitting and opening the app would, and waits for its first agenda.
    func restart() async {
        let applied = module.appliedRefreshes
        await harness.registry.setEnabled(false, for: "calendar")
        await harness.registry.setEnabled(true, for: "calendar")
        await settle { module.appliedRefreshes > applied }
    }

    func tick(to now: Date) async {
        clock.now = now
        let applied = module.appliedRefreshes
        harness.scheduler.advance(by: module.minuteTimerDelay)
        await settle { module.appliedRefreshes > applied }
    }

    /// Moves the clock and the scheduler together, with no waiting, so only what the scheduler itself runs can have
    /// happened when the caller looks.
    func elapse(_ duration: Duration, clockAt now: Date) {
        clock.now = now
        harness.scheduler.advance(by: duration)
    }

    // MARK: Báo lại

    @Test func snoozingHidesTheCardAndItComesBackFiveMinutesLater() async {
        source.events = [standup()]
        await start()
        #expect(meetingEntry != nil)
        #expect(module.state.canSnoozeFeatured)

        module.snoozeMeeting(module.state.featured!)

        #expect(meetingEntry == nil)
        #expect(module.publishedMeeting == nil)
        #expect(!module.state.canSnoozeFeatured)
        #expect(!module.state.canDismissFeatured)
        // The tab keeps showing the event: only the card is hidden.
        #expect(module.state.featured?.id == "standup")

        // One millisecond short of five minutes and the margin: still hidden. The next one brings it back by itself.
        elapse(.milliseconds(300_099), clockAt: calendar.on(14, at: 9, 50, 59))
        #expect(meetingEntry == nil)
        elapse(.milliseconds(1), clockAt: calendar.on(14, at: 9, 51))
        #expect(meetingEntry != nil)
        #expect(module.publishedMeeting?.countdown == "9 phút")
        #expect(module.state.canSnoozeFeatured)
        #expect(module.state.canDismissFeatured)
    }

    @Test func aSnoozeComesBackAtTheStartWhenThatIsSooner() async {
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 57)
        await start()
        module.snoozeMeeting(module.state.featured!)
        #expect(meetingEntry == nil)

        elapse(.milliseconds(179_999), clockAt: calendar.on(14, at: 9, 59, 59))
        #expect(meetingEntry == nil)
        elapse(.milliseconds(101), clockAt: calendar.on(14, at: 10))
        #expect(meetingEntry != nil)
        #expect(module.publishedMeeting?.state == .inProgress)
        #expect(meetingEntry?.activity.priority == .high)
    }

    @Test func aSnoozeCanBeRepeated() async {
        source.events = [standup()]
        await start()
        module.snoozeMeeting(module.state.featured!)
        elapse(.milliseconds(300_100), clockAt: calendar.on(14, at: 9, 51))
        #expect(meetingEntry != nil)
        #expect(module.state.canSnoozeFeatured)

        module.snoozeMeeting(module.state.featured!)
        #expect(meetingEntry == nil)
        elapse(.milliseconds(299_999), clockAt: calendar.on(14, at: 9, 55, 59))
        #expect(meetingEntry == nil)
        elapse(.milliseconds(101), clockAt: calendar.on(14, at: 9, 56))
        #expect(meetingEntry != nil)
        #expect(module.publishedMeeting?.countdown == "4 phút")
    }

    @Test func snoozingNeedsTheMeetingToLieAhead() async {
        source.events = [standup()]
        clock.now = calendar.on(14, at: 10, 1)
        await start()
        #expect(meetingEntry != nil)
        #expect(module.state.canDismissFeatured)
        #expect(!module.state.canSnoozeFeatured)

        module.snoozeMeeting(module.state.featured!)

        #expect(meetingEntry != nil)
        #expect(stored.isEmpty)
    }

    @Test func aSnoozedMeetingStepsAsideForTheNextOne() async {
        source.events = [standup(at: 9, 58), standup(id: "retro", at: 10)]
        await start()
        #expect(module.publishedMeeting?.eventID == "standup")

        module.snoozeMeeting(module.state.featured!)

        #expect(module.publishedMeeting?.eventID == "retro")
        #expect(meetingEntry != nil)
    }

    /// A refresh reads the calendar, which takes a moment; the snooze can end in that moment and the timer bring the
    /// card back. The refresh must then judge the card by the clock as it is when the read is done, not as it was when
    /// the read began, or it hides the card again and shows it again as a new entry.
    @Test func aRefreshThatStraddlesTheEndOfASnoozeLeavesTheCardAlone() async {
        source.events = [standup()]
        await start()
        module.snoozeMeeting(module.state.featured!)
        // Four minute ticks (60.1 s apart) run first and finish, so the straddling refresh is the newest one.
        elapse(.milliseconds(240_400), clockAt: calendar.on(14, at: 9, 50))
        await letAnythingPending()
        #expect(meetingEntry == nil)

        let gate = AsyncGate()
        source.eventsGate = { await gate.wait() }
        clock.now = calendar.on(14, at: 9, 50, 59)
        let refresh = Task { await module.refresh() }
        await settle { gate.waitCalls == 1 }

        // The read is under way; the snooze ends, and its timer brings the card back.
        elapse(.milliseconds(59_700), clockAt: calendar.on(14, at: 9, 51))
        let shown = meetingEntry
        #expect(shown != nil)

        gate.open()
        await refresh.value
        #expect(meetingEntry == shown)
        #expect(module.publishedMeeting?.countdown == "9 phút")
    }

    @Test func theSnoozeTimerLeavesNothingBehindOnceItHasRun() async {
        source.events = [standup()]
        await start()
        let before = harness.scheduler.pendingCount
        module.snoozeMeeting(module.state.featured!)
        #expect(harness.scheduler.pendingCount == before + 1)

        elapse(.milliseconds(300_100), clockAt: calendar.on(14, at: 9, 51))
        #expect(harness.scheduler.pendingCount == before)
    }

    @Test func stoppingTheModuleCancelsAPendingSnooze() async {
        source.events = [standup()]
        await start()
        module.snoozeMeeting(module.state.featured!)

        await harness.registry.setEnabled(false, for: "calendar")

        #expect(harness.scheduler.pendingCount == 0)
        #expect(meetingEntry == nil)
    }

    // MARK: Bỏ qua

    @Test func dismissingHidesTheCardForTheWholeMeeting() async {
        source.events = [standup()]
        await start()
        module.dismissMeeting(module.state.featured!)
        #expect(meetingEntry == nil)

        await tick(to: calendar.on(14, at: 9, 59))
        #expect(meetingEntry == nil)
        await tick(to: calendar.on(14, at: 10, 2))
        #expect(meetingEntry == nil)
        // No timer brings a dismissed card back.
        #expect(harness.scheduler.pendingCount == 1)
    }

    @Test func dismissingOneOccurrenceLeavesTheNextOne() async {
        // A recurring event keeps its item identifier; only the start tells the occurrences apart.
        source.events = [standup()]
        await start()
        module.dismissMeeting(module.state.featured!)
        #expect(meetingEntry == nil)

        source.events = [event("standup", calendar.on(14, at: 10, 30), calendar.on(14, at: 11))]
        await tick(to: calendar.on(14, at: 10, 20))
        #expect(meetingEntry != nil)
    }

    @Test func dismissingAfterASnoozeKeepsItHidden() async {
        source.events = [standup()]
        await start()
        let meeting = module.state.featured!
        module.snoozeMeeting(meeting)
        module.dismissMeeting(meeting)

        elapse(.milliseconds(300_100), clockAt: calendar.on(14, at: 9, 51))
        #expect(meetingEntry == nil)
    }

    // MARK: Join

    @Test func joiningOnlyWorksWithALink() async {
        source.events = [standup()]
        await start()
        module.join(module.state.featured!)
        #expect(opener.urls.isEmpty)
        #expect(meetingEntry != nil)
        #expect(stored.isEmpty)
    }

    @Test func joiningDismissesAndTheDismissalIsStored() async {
        let link = URL(string: "https://whereby.com/acme-standup")!
        source.events = [event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11), meetingURL: link)]
        await start()

        module.join(module.state.featured!)

        #expect(opener.urls == [link])
        #expect(meetingEntry == nil)
        #expect(stored.isHidden(module.state.featured!, now: calendar.on(14, at: 9, 59)))
    }

    // MARK: Persistence

    @Test func theAnswersAreStoredWithTheModulesSettings() async {
        source.events = [standup(), standup(id: "retro", at: 10, 5)]
        await start()
        #expect(stored.isEmpty)

        module.snoozeMeeting(module.state.featured!)
        #expect(stored.count == 1)
        #expect(stored.isHidden(standup(), now: calendar.on(14, at: 9, 50)))
        #expect(!stored.isHidden(standup(), now: calendar.on(14, at: 9, 51)))

        module.dismissMeeting(event("retro", calendar.on(14, at: 10, 5), calendar.on(14, at: 11, 5)))
        #expect(stored.count == 2)
        #expect(keys.meetingReplies.name == "module.calendar.meetingReplies")
    }

    @Test func aDismissalSurvivesARestart() async {
        source.events = [standup()]
        await start()
        module.dismissMeeting(module.state.featured!)
        #expect(meetingEntry == nil)

        await restart()

        #expect(meetingEntry == nil)
        #expect(module.publishedMeeting == nil)
        #expect(module.state.featured?.id == "standup")
        #expect(!module.state.canDismissFeatured)
    }

    @Test func aSnoozeSurvivesARestartAndStillEndsOnTime() async {
        source.events = [standup()]
        await start()
        module.snoozeMeeting(module.state.featured!)

        clock.now = calendar.on(14, at: 9, 48)
        await restart()
        #expect(meetingEntry == nil)

        // The snooze was made at 09:46, so it ends at 09:51: three minutes from the restart.
        elapse(.milliseconds(179_999), clockAt: calendar.on(14, at: 9, 50, 59))
        #expect(meetingEntry == nil)
        elapse(.milliseconds(101), clockAt: calendar.on(14, at: 9, 51))
        #expect(meetingEntry != nil)
    }

    @Test func answersAreLoadedWhenTheModuleStarts() async {
        harness.settings.set(MeetingReplies().dismissing(standup()), for: keys.meetingReplies)
        source.events = [standup()]

        await start()

        #expect(meetingEntry == nil)
        #expect(module.state.featured?.id == "standup")
    }

    @Test func aStoredSnoozeIsHonouredAfterTheAppWasClosed() async {
        harness.settings.set(MeetingReplies().snoozing(standup(), now: calendar.on(14, at: 9, 46)), for: keys.meetingReplies)
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 49)

        await start()

        #expect(meetingEntry == nil)
        // Two minutes to go from the clock's 09:49.
        elapse(.milliseconds(119_999), clockAt: calendar.on(14, at: 9, 50, 59))
        #expect(meetingEntry == nil)
        elapse(.milliseconds(101), clockAt: calendar.on(14, at: 9, 51))
        #expect(meetingEntry != nil)
    }

    @Test func aStoredSnoozeThatRanOutWhileTheAppWasClosedIsGone() async {
        harness.settings.set(MeetingReplies().snoozing(standup(), now: calendar.on(14, at: 9, 46)), for: keys.meetingReplies)
        source.events = [standup()]
        clock.now = calendar.on(14, at: 9, 52)

        await start()

        #expect(meetingEntry != nil)
        #expect(harness.scheduler.pendingCount == 1)
    }

    @Test func anAnswerIsForgottenWhenItsMeetingEnds() async {
        let yesterday = event("old", calendar.on(13, at: 10), calendar.on(13, at: 11))
        harness.settings.set(MeetingReplies().dismissing(yesterday), for: keys.meetingReplies)
        source.events = [standup()]
        await start()
        // Pruned at start, and the pruned map is what is stored.
        #expect(stored.isEmpty)

        module.dismissMeeting(module.state.featured!)
        #expect(stored.count == 1)

        await tick(to: calendar.on(14, at: 10, 59))
        #expect(stored.count == 1)
        await tick(to: calendar.on(14, at: 11))
        #expect(stored.isEmpty)
    }

    @Test func aStoredValueThatCannotBeReadIsNoAnswer() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("not json".utf8), forKey: keys.meetingReplies.name)
        #expect(SettingsStore(defaults: defaults).value(keys.meetingReplies).isEmpty)
    }

    // MARK: The meeting activity among the others

    /// Stands in for the music: normal priority, no expiry, live before the card.
    func playMusic() {
        harness.activities.set(
            LiveActivity(id: "nowPlaying", leading: AnyView(EmptyView()), trailing: AnyView(EmptyView())), from: "media"
        )
    }

    @Test func theCardIsNotANotice() async {
        source.events = [standup()]
        await start()
        #expect(meetingEntry?.activity.expiresAfter == nil)
        #expect(meetingEntry?.activity.priority == .normal)
    }

    @Test func theCardStaysBesideTheMusicUntilItsLastMinute() async {
        playMusic()
        source.events = [standup()]
        await start()
        #expect(harness.activities.current?.id == "media/nowPlaying")
        #expect(harness.activities.others.map(\.id) == ["calendar/meeting"])

        await tick(to: calendar.on(14, at: 9, 59))
        #expect(harness.activities.current?.id == "calendar/meeting")
        #expect(harness.activities.others.map(\.id) == ["media/nowPlaying"])

        await tick(to: calendar.on(14, at: 10, 1, 1))
        #expect(harness.activities.current?.id == "media/nowPlaying")
        #expect(harness.activities.others.map(\.id) == ["calendar/meeting"])
    }

    @Test func aCardThatComesBackAfterASnoozeDoesNotTakeTheNotchFromTheMusic() async {
        playMusic()
        source.events = [standup()]
        await start()
        module.snoozeMeeting(module.state.featured!)
        #expect(harness.activities.entries.map(\.id) == ["media/nowPlaying"])

        elapse(.milliseconds(300_100), clockAt: calendar.on(14, at: 9, 51))

        #expect(harness.activities.current?.id == "media/nowPlaying")
        #expect(harness.activities.others.map(\.id) == ["calendar/meeting"])
    }
}
