import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import TimerModule

/// What happens when a countdown reaches zero: the toast and its buttons, the sound and how long it repeats, what stops it,
/// the pulse, the lock screen, a finish while the app was closed, and what is logged. Sound, time and presenter are fakes, so
/// nothing is played and nothing is shown.
@Suite struct TimerAlertTests {
    let reminder = TimerSession(kind: .reminder, label: "lấy đồ phơi")

    /// A fixture whose countdown of one minute has just finished, under `mode`.
    func finished(
        _ mode: TimerAlertMode = .repeating, kind: TimerKind = .reminder, label: String = "lấy đồ phơi"
    ) async -> TimerFixture {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.setAlert(mode)
        fixture.module.startCountdown(minutes: 1, kind: kind, label: label)
        fixture.advance(60)
        return fixture
    }

    func action(_ title: String, in fixture: TimerFixture) throws -> TimerFinishAction {
        try #require(fixture.module.finishToast.actions.first { $0.title == title }, "no \"\(title)\" button")
    }

    // MARK: Settings

    @Test func theSoundSettingOffersThreeChoicesAndRepeatsByDefault() {
        let fixture = TimerFixture()
        #expect(TimerAlertMode.allCases.map(\.title) == ["Một lần", "Lặp đến khi tắt", "Không"])
        #expect(fixture.settings.value(fixture.keys.alertMode) == .repeating)
        #expect(fixture.keys.alertMode.name == "module.timer.alertMode")
        #expect(fixture.settings.value(fixture.keys.alertSound) == "Glass")
        #expect(TimerAlertSound.names == ["Glass", "Ping", "Hero", "Submarine"])
    }

    @Test func aSoundThatIsNotOnTheListFallsBackToGlass() {
        #expect(TimerAlertSound.resolved("Hero") == "Hero")
        #expect(TimerAlertSound.resolved("") == "Glass")
        #expect(TimerAlertSound.resolved("../../etc/passwd") == "Glass")
    }

    // MARK: The toast

    @Test func oneToastPerFinishWhateverHappensAfterIt() async {
        let fixture = await finished()
        #expect(fixture.harness.presenter.toastCount == 1)
        fixture.advance(300)
        #expect(fixture.harness.presenter.toastCount == 1)
    }

    @Test func theToastSaysHowTheTimerEndedAndWhatItWasFor() async {
        #expect(await finished(kind: .reminder, label: "lấy đồ phơi").module.finishToast.title == "Hết giờ · lấy đồ phơi")
        #expect(await finished(kind: .reminder, label: "").module.finishToast.title == "Hết giờ")
        #expect(await finished(kind: .task, label: "").module.finishToast.title == "Hết giờ tập trung")
        #expect(await finished(kind: .rest, label: "").module.finishToast.title == "Hết giờ nghỉ")
    }

    @Test func theToastOffersTheNextStepOnlyWhereThereIsOne() async {
        func titles(_ kind: TimerKind) async -> [String] {
            await finished(kind: kind, label: "").module.finishToast.actions.map(\.title)
        }
        #expect(await titles(.reminder) == ["+5 phút", "Tắt"])
        #expect(await titles(.task) == ["Bắt đầu nghỉ", "+5 phút", "Tắt"])
        #expect(await titles(.rest) == ["Bắt đầu tập trung", "+5 phút", "Tắt"])
    }

    @Test func tatDismissesTheTimerAndClosesTheNotch() async throws {
        let fixture = await finished()
        try action("Tắt", in: fixture).run()
        #expect(fixture.module.state.model == .idle)
        #expect(fixture.harness.presenter.closeCount == 1)
        #expect(fixture.harness.activities.current == nil)
        #expect(!fixture.module.state.isAlerting)
        #expect(fixture.sound.stopCount >= 1)
    }

    @Test func fivePlusMinutesRestartsTheSameTimerForFiveMinutes() async throws {
        let fixture = await finished(kind: .reminder, label: "lấy đồ phơi")
        try action("+5 phút", in: fixture).run()
        #expect(fixture.module.state.model == .countdown(endDate: fixture.clock.date.addingTimeInterval(300)))
        #expect(fixture.module.state.session == reminder)
        #expect(try fixture.saved() == StoredTimer(model: .countdown(endDate: fixture.clock.date.addingTimeInterval(300)), session: reminder))
        #expect(fixture.harness.presenter.closeCount == 1)
        #expect(!fixture.module.state.isAlerting)

        // When it ends again it is announced again, from the start.
        let before = fixture.sound.played.count
        fixture.advance(300)
        #expect(fixture.harness.presenter.toastCount == 2)
        #expect(fixture.sound.played.count == before + 1)
        #expect(fixture.module.state.isAlerting)
    }

    @Test func snoozingATaskKeepsItATask() async throws {
        let fixture = await finished(kind: .task, label: "")
        try action("+5 phút", in: fixture).run()
        #expect(fixture.module.state.session == TimerSession(kind: .task, label: ""))
        #expect(fixture.module.state.model == .countdown(endDate: fixture.clock.date.addingTimeInterval(300)))
    }

    @Test func batDauNghiStartsABreakOfTheLengthSetInSettings() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.settings.set(7, for: fixture.keys.rest)
        fixture.module.startCountdown(minutes: 1, kind: .task)
        fixture.advance(60)
        try action("Bắt đầu nghỉ", in: fixture).run()
        #expect(fixture.module.state.session == TimerSession(kind: .rest, label: ""))
        #expect(fixture.module.state.model == .countdown(endDate: fixture.clock.date.addingTimeInterval(420)))
        #expect(fixture.harness.presenter.closeCount == 1)
        #expect(!fixture.module.state.isAlerting)
    }

    @Test func aBreakOffersToGetBackToWork() async throws {
        let fixture = await finished(kind: .rest, label: "")
        try action("Bắt đầu tập trung", in: fixture).run()
        #expect(fixture.module.state.session.kind == .task)
        #expect(fixture.module.state.model == .countdown(endDate: fixture.clock.date.addingTimeInterval(1_500)))
    }

    /// The toast can outlive the moment: a button of an old toast must not touch a timer started since.
    @Test func aButtonOfAnOldToastLeavesANewTimerAlone() async throws {
        let fixture = await finished(kind: .task, label: "")
        let old = fixture.module.finishToast.actions
        fixture.module.startCountdown(minutes: 10, kind: .reminder, label: "Gọi mẹ")
        let running = fixture.module.state.model
        for button in old { button.run() }
        #expect(fixture.module.state.model == running)
        #expect(fixture.module.state.session.label == "Gọi mẹ")
    }

    @Test func aCountdownThatIsOverdueAndThenCancelledIsNotAnnounced() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 1)
        fixture.clock.advance(61)   // past the end, but the finish timer has not run
        fixture.module.cancel()
        #expect(fixture.harness.presenter.toastCount == 0)
        #expect(fixture.sound.played.isEmpty)
        #expect(!fixture.module.state.isAlerting)
        fixture.harness.scheduler.advance(by: .seconds(600))
        #expect(fixture.harness.presenter.toastCount == 0)
    }

    // MARK: The sound

    @Test func theRepeatingSoundPlaysEveryThreeSecondsAndStopsAfterSixty() async {
        let fixture = await finished(.repeating)
        #expect(fixture.sound.played == ["Glass"])
        fixture.advance(2)
        #expect(fixture.sound.played.count == 1)
        fixture.advance(1)
        #expect(fixture.sound.played.count == 2)
        fixture.advance(54)   // 57 s: the twentieth and last
        #expect(fixture.sound.played.count == 20)
        fixture.advance(3)
        #expect(fixture.sound.played.count == 20)
        fixture.advance(600)
        #expect(fixture.sound.played.count == 20)
        #expect(Set(fixture.sound.played) == ["Glass"])
    }

    @Test func theCapAndTheCadenceAreWhatTheBriefSays() {
        #expect(TimerModule.repeatInterval == .seconds(3))
        #expect(TimerModule.alertLifetime == .seconds(60))
    }

    @Test func onceMeansOneSound() async {
        let fixture = await finished(.once)
        fixture.advance(600)
        #expect(fixture.sound.played == ["Glass"])
        #expect(fixture.harness.presenter.toastCount == 1)
    }

    @Test func offMeansNoSoundButTheToastAndThePulseStay() async {
        let fixture = await finished(.off)
        #expect(fixture.module.state.isAlerting)
        #expect(fixture.harness.activities.current?.activity.priority == .high)
        fixture.advance(55)
        #expect(fixture.sound.played.isEmpty)
        #expect(fixture.harness.presenter.toastCount == 1)
        #expect(fixture.module.state.isAlerting)
    }

    @Test func theChosenSoundIsTheOneThatPlays() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.setAlert(.repeating)
        fixture.setAlertSound("Submarine")
        fixture.module.startCountdown(minutes: 1)
        fixture.advance(63)
        #expect(fixture.sound.played == ["Submarine", "Submarine"])
    }

    @Test func aSavedSoundThatIsNotOnTheListPlaysGlass() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.setAlert(.once)
        fixture.setAlertSound("Nope")
        fixture.module.startCountdown(minutes: 1)
        fixture.advance(60)
        #expect(fixture.sound.played == ["Glass"])
    }

    /// Changing the setting while a timer runs applies to the finish, not to the start.
    @Test func theSettingIsReadWhenTheTimerEnds() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.setAlert(.repeating)
        fixture.module.startCountdown(minutes: 1)
        fixture.setAlert(.off)
        fixture.advance(60)
        #expect(fixture.sound.played.isEmpty)
    }

    // MARK: What stops the sound

    enum StopEvent: String, CaseIterable, CustomTestStringConvertible {
        case dismissButton, snoozeButton, breakButton, tabOpened, newTimer, newStopwatch, tabsPlusMinute, tabsClose, pauseAll, disabled

        var testDescription: String { rawValue }

        func apply(to fixture: TimerFixture) async {
            switch self {
            case .dismissButton: fixture.module.finishToast.actions.first { $0.title == "Tắt" }?.run()
            case .snoozeButton: fixture.module.finishToast.actions.first { $0.title == "+5 phút" }?.run()
            case .breakButton: fixture.module.finishToast.actions.first { $0.title == "Bắt đầu nghỉ" }?.run()
            case .tabOpened: fixture.module.acknowledgeFinish()
            case .newTimer: fixture.module.startCountdown(minutes: 30, kind: .reminder, label: "Gọi mẹ")
            case .newStopwatch: fixture.module.startStopwatch()
            case .tabsPlusMinute: fixture.module.addMinute()
            case .tabsClose: fixture.module.cancel()
            case .pauseAll: await fixture.harness.registry.pauseAll()
            case .disabled: await fixture.harness.registry.setEnabled(false, for: "timer")
            }
        }
    }

    @Test(arguments: StopEvent.allCases)
    func theRepeatStopsOn(_ event: StopEvent) async {
        let fixture = await finished(.repeating, kind: .task, label: "")
        fixture.advance(7)   // three sounds so far
        #expect(fixture.sound.played.count == 3)
        let stops = fixture.sound.stopCount
        await event.apply(to: fixture)
        #expect(fixture.sound.stopCount > stops, "the sound that is playing is stopped, not only the repeat")
        #expect(!fixture.module.state.isAlerting)
        let played = fixture.sound.played.count
        fixture.advance(50)   // shorter than a minute, so a "+1 phút" countdown has not ended again
        #expect(fixture.sound.played.count == played)
    }

    @Test func openingTheTabSilencesTheAlertButLeavesTheFinishedTimerWhereItIs() async {
        let fixture = await finished()
        fixture.module.acknowledgeFinish()
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.harness.activities.current?.activity.priority == .high)
        #expect(fixture.harness.lockScreen.current == nil)
        // Nothing to acknowledge any more: opening the tab again does nothing.
        let stops = fixture.sound.stopCount
        fixture.module.acknowledgeFinish()
        #expect(fixture.sound.stopCount == stops)
    }

    @Test func openingTheTabWithNothingFinishedDoesNothing() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 5)
        fixture.module.acknowledgeFinish()
        #expect(fixture.sound.stopCount == 0)
        #expect(fixture.module.state.model != .idle)
    }

    @Test func theTabViewAcknowledgesTheAlertWhenItAppears() async {
        let fixture = await finished()
        #expect(fixture.module.state.isAlerting)
        let hosting = NSHostingView(rootView: TimerTabView(state: fixture.module.state, module: fixture.module))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 452, height: 170), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        for _ in 0..<40 where fixture.module.state.isAlerting { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(!fixture.module.state.isAlerting)
        window.contentView = nil
    }

    // MARK: Attention

    func descendants(of view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }

    /// How many pulsing views the content has: the pulse runs on the layer of the glyph's own hosting view.
    func pulsingViews(in content: AnyView) -> (found: Int, pulsing: Int) {
        let hosting = NSHostingView(rootView: content.frame(width: 70, height: 24))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 80, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let pulses = descendants(of: hosting).filter { String(describing: type(of: $0)).hasPrefix("NotchPulseView") }
        let pulsing = pulses.filter { $0.subviews.first?.layer?.animationKeys()?.isEmpty == false }.count
        window.contentView = nil
        return (pulses.count, pulsing)
    }

    @Test func theFinishedActivityPulsesWhileTheAlertLastsOnEveryPartOfIt() async throws {
        let fixture = await finished()
        let activity = try #require(fixture.harness.activities.current?.activity)
        let minimal = try #require(activity.minimal)
        for (name, view) in [("leading", activity.leading), ("trailing", activity.trailing), ("minimal", minimal)] {
            let reading = pulsingViews(in: view)
            #expect(reading.found == 1 && reading.pulsing == 1, "\(name) pulses")
        }
    }

    @Test func thePulseStopsWithoutRepublishingTheActivity() async throws {
        let fixture = await finished()
        let shown = try #require(fixture.harness.activities.current)
        fixture.module.acknowledgeFinish()
        // The same entry: republishing would have restarted its lifetime.
        #expect(fixture.harness.activities.current == shown)
        for view in [shown.activity.leading, shown.activity.trailing] {
            let reading = pulsingViews(in: view)
            #expect(reading.found == 1 && reading.pulsing == 0)
        }
    }

    @Test func aRunningTimerDoesNotPulse() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 5, kind: .reminder, label: "x")
        let activity = try #require(fixture.harness.activities.current?.activity)
        #expect(pulsingViews(in: activity.leading).pulsing == 0)
    }

    @Test func theFinishedActivityLivesAsLongAsTheAlert() async {
        let fixture = await finished(.once)
        #expect(fixture.harness.activities.current?.activity.expiresAfter == TimerModule.alertLifetime)
    }

    // MARK: Lock screen

    /// Pixels that are clearly red: the finished glyph. A running countdown on the same card is the type's own accent.
    func redPixels(in entry: LockScreenContentCenter.Entry) throws -> Int {
        let renderer = ImageRenderer(content: entry.view.frame(width: 340, height: 70).background(Color.black))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if colour.redComponent > 0.7, colour.greenComponent < 0.4, colour.blueComponent < 0.4 { count += 1 }
            }
        }
        return count
    }

    @Test func aFinishedTimerShowsHetGioOnTheLockScreen() async throws {
        let running = TimerFixture()
        await running.start()
        running.module.startCountdown(minutes: 5, kind: .reminder, label: "lấy đồ phơi")
        #expect(try redPixels(in: #require(running.harness.lockScreen.current)) == 0)

        let fixture = await finished()
        let entry = try #require(fixture.harness.lockScreen.current)
        #expect(entry.module == "timer")
        #expect(entry.priority == .high)
        #expect(try redPixels(in: entry) > 20)
        #expect(TimerFinishedLockScreenView(session: reminder).text == "Hết giờ · lấy đồ phơi")
        #expect(fixture.sound.played == ["Glass"], "the sound plays whatever the lock screen shows")
    }

    @Test func theFinishedLockScreenGoesWhenTheUserDismissesOrOpensTheTab() async {
        let dismissed = await finished()
        dismissed.module.cancel()
        #expect(dismissed.harness.lockScreen.current == nil)

        let opened = await finished()
        opened.module.acknowledgeFinish()
        #expect(opened.harness.lockScreen.current == nil)
    }

    @Test func snoozingPutsTheRunningTimeBackOnTheLockScreenInPlaceOfTheFinishedText() async throws {
        let fixture = await finished()
        fixture.module.snooze()
        let entry = try #require(fixture.harness.lockScreen.current)
        #expect(try redPixels(in: entry) == 0)
    }

    @Test func theFinishedLockScreenIsGoneWithTheModule() async {
        let fixture = await finished()
        await fixture.harness.registry.setEnabled(false, for: "timer")
        #expect(fixture.harness.lockScreen.current == nil)
    }

    // MARK: A finish while the app was closed

    func launched(endedSecondsAgo seconds: TimeInterval, label: String = "lấy đồ phơi") async throws -> TimerFixture {
        let fixture = TimerFixture()
        try fixture.seedFile(.countdown(endDate: fixture.clock.date.addingTimeInterval(-seconds)), session: TimerSession(kind: .reminder, label: label))
        await fixture.start()
        return fixture
    }

    @Test func aFinishJustBeforeLaunchIsAnnouncedWithToastSoundAndLockScreen() async throws {
        let fixture = try await launched(endedSecondsAgo: 119)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.harness.presenter.toastCount == 1)
        #expect(fixture.sound.played == ["Glass"])
        #expect(fixture.module.state.isAlerting)
        #expect(fixture.harness.lockScreen.current?.priority == .high)
        #expect(fixture.harness.activities.current?.activity.expiresAfter == TimerModule.alertLifetime)
        fixture.advance(3)
        #expect(fixture.sound.played.count == 2)
    }

    @Test func aFinishTwoMinutesBeforeLaunchIsOnlyShown() async throws {
        let fixture = try await launched(endedSecondsAgo: 120)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.harness.presenter.toastCount == 0)
        #expect(fixture.sound.played.isEmpty)
        #expect(!fixture.module.state.isAlerting)
        #expect(fixture.harness.lockScreen.current == nil)
        // As before: the high activity with the label, for the usual 30 s.
        #expect(fixture.harness.activities.current?.activity.priority == .high)
        #expect(fixture.harness.activities.current?.activity.summary == "Hết giờ: lấy đồ phơi")
        #expect(fixture.harness.activities.current?.activity.expiresAfter == .seconds(30))
        fixture.advance(600)
        #expect(fixture.sound.played.isEmpty)
    }

    @Test func aTimerThatWasFinishedWhenTheAppClosedIsNeverAnnouncedAtLaunch() async throws {
        let fixture = TimerFixture()
        try fixture.seedFile(.finished, session: reminder)
        await fixture.start()
        #expect(fixture.harness.presenter.toastCount == 0)
        #expect(fixture.sound.played.isEmpty)
        #expect(fixture.harness.lockScreen.current == nil)
        #expect(fixture.harness.activities.current == nil)
    }

    /// Quitting during an alert and starting again must not ring a second time: what was saved is a finished timer.
    @Test func relaunchingDuringAnAlertDoesNotAnnounceItAgain() async throws {
        let fixture = await finished()
        #expect(fixture.harness.presenter.toastCount == 1)
        await fixture.harness.registry.setEnabled(false, for: "timer")
        await fixture.harness.registry.setEnabled(true, for: "timer")
        #expect(fixture.harness.presenter.toastCount == 1)
        #expect(!fixture.module.state.isAlerting)
        fixture.advance(600)
        #expect(fixture.sound.played.count == 1)
    }

    // MARK: Logging

    final class Lines { var all: [String] = [] }

    @Test func theFinishIsLoggedWithItsTypeAndLatenessAndNeverItsLabel() async throws {
        let lines = Lines()
        let fixture = TimerFixture()
        fixture.module.logObserver = { lines.all.append($0) }
        await fixture.start()
        fixture.module.startCountdown(minutes: 1, kind: .reminder, label: "lấy đồ phơi")
        fixture.clock.advance(65)   // the clock ran 5 s past the end before the timer fired
        fixture.harness.scheduler.advance(by: .seconds(60))
        #expect(lines.all == ["Countdown finished: type=reminder late=5s"])
        #expect(!lines.all.joined().contains("phơi"))
    }

    @Test func aFinishAtLaunchIsLoggedToo() async throws {
        let lines = Lines()
        let fixture = TimerFixture()
        fixture.module.logObserver = { lines.all.append($0) }
        try fixture.seedFile(.countdown(endDate: fixture.clock.date.addingTimeInterval(-300)), session: reminder)
        await fixture.start()
        #expect(lines.all == ["Countdown finished: type=reminder late=300s"])
    }

    @Test func theLogLineNamesTheTypeAndRoundsTheLateness() {
        #expect(TimerModule.finishLogMessage(kind: .task, lateness: 0) == "Countdown finished: type=task late=0s")
        #expect(TimerModule.finishLogMessage(kind: .rest, lateness: 1.6) == "Countdown finished: type=rest late=2s")
    }

    // MARK: The session's words

    @Test func theHeadlineIsOneTextForTheToastAndTheLockScreen() {
        #expect(reminder.finishedHeadline == "Hết giờ · lấy đồ phơi")
        #expect(TimerSession.plain.finishedHeadline == "Hết giờ")
        #expect(TimerSuggestion(kind: .rest, minutes: 5).toastTitle == "Bắt đầu nghỉ")
        #expect(TimerSuggestion(kind: .task, minutes: 25).toastTitle == "Bắt đầu tập trung")
    }
}
