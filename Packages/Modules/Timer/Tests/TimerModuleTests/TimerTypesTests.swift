import Foundation
import MyNotchCore
import Testing
@testable import TimerModule

/// The three timer types on top of the countdown engine: what each start records, what is offered when one ends,
/// where the dial starts, what survives a restart and what the notch shows. Time and sound are fakes throughout.
@Suite struct TimerTypesTests {
    let reminder = TimerSession(kind: .reminder, label: "Gọi mẹ")

    // MARK: Starting each type

    @Test func startingATimerRecordsItsTypeAndSavesIt() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 25, kind: .task)
        #expect(fixture.module.state.session == TimerSession(kind: .task, label: ""))
        #expect(fixture.module.state.model == .countdown(endDate: fixture.clock.date.addingTimeInterval(1_500)))
        #expect(try fixture.saved() == StoredTimer(
            model: .countdown(endDate: fixture.clock.date.addingTimeInterval(1_500)),
            session: TimerSession(kind: .task, label: "")))
    }

    @Test func aReminderKeepsItsTrimmedLabel() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 10, kind: .reminder, label: "  Gọi mẹ ")
        #expect(fixture.module.state.session == reminder)
        #expect(try fixture.saved().session == reminder)
    }

    @Test func aCountdownStartedWithoutATypeIsAPlainReminder() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 5)
        #expect(fixture.module.state.session == .plain)
    }

    @Test func aTimerOfZeroMinutesIsNotStarted() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 0, kind: .task)
        #expect(fixture.module.state.model == .idle)
        #expect(fixture.harness.activities.current == nil)
        #expect(fixture.harness.scheduler.pendingCount == 0)
    }

    @Test func startingANewTypeReplacesTheOneThatRuns() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 25, kind: .task)
        fixture.module.startCountdown(minutes: 10, kind: .reminder, label: "Gọi mẹ")
        #expect(fixture.module.state.session == reminder)
        #expect(fixture.module.state.model == .countdown(endDate: fixture.clock.date.addingTimeInterval(600)))
        #expect(fixture.harness.scheduler.pendingCount == 1)
    }

    @Test func addingAMinuteToAFinishedTaskKeepsItATask() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 1, kind: .task)
        fixture.advance(60)
        fixture.module.addMinute()
        #expect(fixture.module.state.session.kind == .task)
        #expect(fixture.module.suggestion == nil)
        fixture.advance(60)
        #expect(fixture.module.suggestion == TimerSuggestion(kind: .rest, minutes: 5))
    }

    // MARK: What is offered when one ends

    @Test func whenATaskEndsABreakIsOffered() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 25, kind: .task)
        #expect(fixture.module.suggestion == nil)
        fixture.advance(1_499)
        #expect(fixture.module.suggestion == nil)
        fixture.advance(1)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.module.suggestion == TimerSuggestion(kind: .rest, minutes: 5))
        #expect(fixture.sound.played == ["Glass"])
    }

    @Test func takingTheBreakRunsItAndATaskIsOfferedWhenItEnds() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 25, kind: .task)
        fixture.advance(1_500)
        fixture.module.startNext()
        #expect(fixture.module.state.session == TimerSession(kind: .rest, label: ""))
        #expect(fixture.module.state.model == .countdown(endDate: fixture.clock.date.addingTimeInterval(300)))
        #expect(fixture.module.suggestion == nil)

        fixture.advance(300)
        #expect(fixture.module.suggestion == TimerSuggestion(kind: .task, minutes: 25))
        fixture.module.startNext()
        #expect(fixture.module.state.session == TimerSession(kind: .task, label: ""))
        #expect(fixture.module.state.model == .countdown(endDate: fixture.clock.date.addingTimeInterval(1_500)))
        #expect(fixture.sound.played == ["Glass", "Glass"])
    }

    @Test func aReminderOffersNothingWhenItEnds() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 10, kind: .reminder, label: "Gọi mẹ")
        fixture.advance(600)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.module.suggestion == nil)
        fixture.module.startNext()
        #expect(fixture.module.state.model == .finished)
    }

    @Test func nothingIsOfferedOnceTheFinishedTimerIsDismissed() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 25, kind: .task)
        fixture.advance(1_500)
        fixture.module.cancel()
        #expect(fixture.module.suggestion == nil)
        fixture.module.startNext()
        #expect(fixture.module.state.model == .idle)
    }

    @Test func theOfferedLengthsFollowTheSettings() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        let settings = try #require(fixture.harness.settingsEnvironment(for: "timer")).settings
        let keys = TimerSettingsKeys(settings)
        settings.set(30, for: keys.task)
        settings.set(8, for: keys.rest)

        fixture.module.startCountdown(minutes: 30, kind: .task)
        fixture.advance(1_800)
        #expect(fixture.module.suggestion == TimerSuggestion(kind: .rest, minutes: 8))
        fixture.module.startNext()
        #expect(fixture.module.state.model == .countdown(endDate: fixture.clock.date.addingTimeInterval(480)))
        fixture.advance(480)
        #expect(fixture.module.suggestion == TimerSuggestion(kind: .task, minutes: 30))
    }

    // MARK: The dial's starting point

    @Test func theDialStartsAtEachTypesDefaultLength() async {
        let fixture = TimerFixture()
        await fixture.start()
        #expect(fixture.module.minutes(for: .task) == 25)
        #expect(fixture.module.minutes(for: .reminder) == 10)
        #expect(fixture.module.minutes(for: .rest) == 5)
    }

    @Test func aSettingChangesWhereTheDialStartsAndStaysOnTheDial() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        let settings = try #require(fixture.harness.settingsEnvironment(for: "timer")).settings
        let keys = TimerSettingsKeys(settings)
        settings.set(40, for: keys.task)
        #expect(fixture.module.minutes(for: .task) == 40)
        #expect(fixture.module.minutes(for: .rest) == 5)
        settings.set(99, for: keys.task)
        #expect(fixture.module.minutes(for: .task) == 60)
        settings.set(0, for: keys.task)
        #expect(fixture.module.minutes(for: .task) == 1)
    }

    @Test func turningTheDialOverridesTheSettingUntilATimerStarts() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.setMinutes(45, for: .task)
        fixture.module.setMinutes(7, for: .rest)
        #expect(fixture.module.minutes(for: .task) == 45)
        #expect(fixture.module.minutes(for: .rest) == 7)
        #expect(fixture.module.minutes(for: .reminder) == 10)

        fixture.module.startCountdown(minutes: 45, kind: .task)
        #expect(fixture.module.minutes(for: .task) == 25)
        #expect(fixture.module.minutes(for: .rest) == 7)
    }

    @Test func theDialNeverLeavesItsRange() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.setMinutes(90, for: .task)
        #expect(fixture.module.minutes(for: .task) == 60)
        fixture.module.setMinutes(-4, for: .task)
        #expect(fixture.module.minutes(for: .task) == 0)
    }

    @Test func theSettingsRowsExistBeforeTheModuleStarts() {
        let fixture = TimerFixture()
        let view = fixture.harness.registry.settingsView(for: "timer")
        #expect(view != nil)
        #expect(String(describing: view as Any).contains("TimerSettingsView"))
    }

    @Test func theDefaultsAreTheSettingsDefaults() {
        let fixture = TimerFixture()
        let keys = TimerSettingsKeys(fixture.harness.settingsEnvironment(for: "timer")!.settings)
        #expect(keys.task.defaultValue == 25)
        #expect(keys.reminder.defaultValue == 10)
        #expect(keys.rest.defaultValue == 5)
        #expect(keys.key(for: .rest).name == "module.timer.breakMinutes")
    }

    // MARK: Restart

    @Test func aRunningReminderResumesWithItsLabelAndFiresAtTheEnd() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 10, kind: .reminder, label: "Gọi mẹ")
        await fixture.harness.registry.setEnabled(false, for: "timer")
        fixture.clock.advance(100)
        await fixture.harness.registry.setEnabled(true, for: "timer")
        #expect(fixture.module.state.session == reminder)
        #expect(fixture.module.state.model.remaining(now: fixture.clock.date) == 500)
        #expect(fixture.harness.activities.current?.activity.summary == "Nhắc việc: Gọi mẹ")

        fixture.advance(500)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.sound.played == ["Glass"])
        #expect(fixture.harness.activities.current?.activity.summary == "Hết giờ: Gọi mẹ")
    }

    @Test func aTimerPastItsEndWhenTheAppStartsFiresAtOnceWithItsLabel() async throws {
        let fixture = TimerFixture()
        try fixture.seedFile(.countdown(endDate: fixture.clock.date.addingTimeInterval(-5)), session: reminder)
        await fixture.start()
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.module.state.session == reminder)
        #expect(fixture.harness.activities.current?.activity.priority == .high)
        #expect(fixture.harness.activities.current?.activity.summary == "Hết giờ: Gọi mẹ")
        #expect(try fixture.saved() == StoredTimer(model: .finished, session: reminder))
    }

    @Test func aRunningTaskResumesAndOffersABreakWhenItEnds() async throws {
        let fixture = TimerFixture()
        try fixture.seedFile(.countdown(endDate: fixture.clock.date.addingTimeInterval(400)), session: TimerSession(kind: .task, label: ""))
        await fixture.start()
        #expect(fixture.module.state.session.kind == .task)
        #expect(fixture.module.suggestion == nil)
        fixture.advance(400)
        #expect(fixture.module.suggestion == TimerSuggestion(kind: .rest, minutes: 5))
    }

    @Test func aTaskThatEndedWhileTheAppWasClosedStillOffersABreak() async throws {
        let fixture = TimerFixture()
        try fixture.seedFile(.countdown(endDate: fixture.clock.date.addingTimeInterval(-60)), session: TimerSession(kind: .task, label: ""))
        await fixture.start()
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.module.suggestion == TimerSuggestion(kind: .rest, minutes: 5))
        #expect(fixture.sound.played.isEmpty)
    }

    @Test func aPausedBreakIsRestoredAsABreak() async throws {
        let fixture = TimerFixture()
        try fixture.seedFile(.countdownPaused(remaining: 77), session: TimerSession(kind: .rest, label: ""))
        await fixture.start()
        #expect(fixture.module.state.session.kind == .rest)
        #expect(fixture.module.state.model == .countdownPaused(remaining: 77))
        #expect(fixture.harness.activities.current == nil)
    }

    @Test func aFileFromBeforeTheTypesResumesAsAPlainTimer() async throws {
        let fixture = TimerFixture()
        try fixture.seedLegacyFile(.countdown(endDate: fixture.clock.date.addingTimeInterval(400)))
        await fixture.start()
        #expect(fixture.module.state.session == .plain)
        #expect(fixture.module.state.model.remaining(now: fixture.clock.date) == 400)
        fixture.advance(400)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.sound.played == ["Glass"])
    }

    @Test func theSessionIsSavedWithEveryChange() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 10, kind: .reminder, label: "Gọi mẹ")
        fixture.advance(60)
        fixture.module.pause()
        #expect(try fixture.saved() == StoredTimer(model: .countdownPaused(remaining: 540), session: reminder))
        fixture.module.cancel()
        #expect(try fixture.saved().model == .idle)
    }

    // MARK: Live activity

    @Test func aRunningTaskShowsItsGlyphAndNameInTheNotch() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 25, kind: .task)
        let activity = try #require(fixture.harness.activities.current?.activity)
        #expect(activity.summary == "Tập trung")
        #expect(activity.minimal != nil)
        #expect(!activity.hasBottom)
        #expect(String(describing: activity.leading).contains(TimerKind.task.systemImage))
        #expect(String(describing: activity.minimal as Any).contains(TimerKind.task.systemImage))
    }

    @Test func aRunningBreakShowsItsOwnGlyph() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 5, kind: .rest)
        let activity = try #require(fixture.harness.activities.current?.activity)
        #expect(activity.summary == "Nghỉ")
        #expect(String(describing: activity.leading).contains(TimerKind.rest.systemImage))
        #expect(!String(describing: activity.leading).contains(TimerKind.task.systemImage))
    }

    @Test func aRunningReminderShowsItsLabelUnderTheNotch() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 10, kind: .reminder, label: "Gọi mẹ")
        let activity = try #require(fixture.harness.activities.current?.activity)
        #expect(activity.summary == "Nhắc việc: Gọi mẹ")
        #expect(activity.hasBottom)
        #expect(activity.minimal != nil)
        #expect(String(describing: activity.leading).contains(TimerKind.reminder.systemImage))
        #expect(String(describing: activity.bottom as Any).contains("Gọi mẹ"))
    }

    @Test func aReminderWithoutALabelNeedsNoStripUnderTheNotch() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 10, kind: .reminder)
        let activity = try #require(fixture.harness.activities.current?.activity)
        #expect(activity.summary == "Nhắc việc")
        #expect(!activity.hasBottom)
    }

    @Test func aFinishedReminderPutsItsLabelInTheActivity() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 10, kind: .reminder, label: "Gọi mẹ")
        fixture.advance(600)
        let activity = try #require(fixture.harness.activities.current?.activity)
        #expect(activity.priority == .high)
        #expect(activity.summary == "Hết giờ: Gọi mẹ")
        #expect(activity.hasBottom)
        #expect(String(describing: activity.bottom as Any).contains("Gọi mẹ"))
        #expect(activity.expiresAfter == .seconds(30))
        #expect(activity.minimal != nil)
    }

    @Test func aFinishedTaskSaysSoWithoutAStrip() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 25, kind: .task)
        fixture.advance(1_500)
        let activity = try #require(fixture.harness.activities.current?.activity)
        #expect(activity.summary == "Hết giờ tập trung")
        #expect(!activity.hasBottom)
        #expect(activity.minimal != nil)
    }

    @Test func aStopwatchSaysWhatItIs() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startStopwatch()
        let activity = try #require(fixture.harness.activities.current?.activity)
        #expect(activity.summary == "Bấm giờ")
        #expect(activity.minimal != nil)
        #expect(!activity.hasBottom)
    }

    @Test func aRunningTypedTimerStillGoesToTheLockScreen() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 25, kind: .task)
        #expect(fixture.harness.lockScreen.current?.module == "timer")
    }
}
