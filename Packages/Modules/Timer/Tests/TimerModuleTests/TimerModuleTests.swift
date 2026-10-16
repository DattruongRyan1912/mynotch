import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import TimerModule

/// Records instead of playing, so tests are silent.
final class FakeSoundPlayer: SoundPlaying {
    private(set) var played: [String] = []
    private(set) var stopCount = 0
    func play(named name: String) { played.append(name) }
    func stop() { stopCount += 1 }
}

final class FakeClock {
    var date = Date(timeIntervalSinceReferenceDate: 1_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
struct TimerFixture {
    let clock = FakeClock()
    let sound = FakeSoundPlayer()
    let module: TimerModule
    let harness: RegistryHarness

    init() {
        let clock = clock, sound = sound
        module = TimerModule(now: { clock.date }, sound: sound)
        harness = RegistryHarness([module])
    }

    var fileURL: URL { harness.storageRoot.storage(for: "timer").directory.appending(path: "timer.json") }

    func start() async { await harness.registry.bootstrap() }

    /// The module's settings as Settings would change them, whether or not the module runs.
    var settings: ModuleSettings { harness.settingsEnvironment(for: "timer")!.settings }
    var keys: TimerSettingsKeys { TimerSettingsKeys(settings) }

    /// What the sound at the end of a countdown does ("Âm báo hết giờ"). The shipped default repeats, so a test about
    /// something else that lets time pass after a finish picks `.once`.
    func setAlert(_ mode: TimerAlertMode) { settings.set(mode, for: keys.alertMode) }
    func setAlertSound(_ name: String) { settings.set(name, for: keys.alertSound) }

    /// Moves both the wall clock and the scheduler, as real time does.
    func advance(_ seconds: Int) {
        clock.advance(TimeInterval(seconds))
        harness.scheduler.advance(by: .seconds(seconds))
    }

    func seedFile(_ model: TimerModel, session: TimerSession = .plain) throws {
        try write(JSONEncoder().encode(StoredTimer(model: model, session: session)))
    }

    /// The file as the version before the timer types wrote it: the bare model.
    func seedLegacyFile(_ model: TimerModel) throws {
        try write(JSONEncoder().encode(model))
    }

    private func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    func saved() throws -> StoredTimer {
        try JSONDecoder().decode(StoredTimer.self, from: Data(contentsOf: fileURL))
    }

    func savedModel() throws -> TimerModel { try saved().model }
}

@Suite struct TimerModuleTests {
    @Test func descriptorAndTab() async throws {
        let fixture = TimerFixture()
        #expect(fixture.module.descriptor.id == "timer")
        #expect(fixture.module.descriptor.displayName == "Hẹn giờ")
        #expect(fixture.module.descriptor.systemImage == "timer")
        #expect(fixture.module.descriptor.order == 880)
        let tab = try #require(fixture.module.makeTab())
        #expect(tab.title == "Hẹn giờ")
        #expect(tab.preferredHeight == TimerTabView.preferredHeight)
        #expect(tab.acceptsKeyboard)
    }

    @Test func runningCountdownPublishesOneActivityWithoutPerSecondUpdates() async {
        let fixture = TimerFixture()
        await fixture.start()
        #expect(fixture.harness.activities.current == nil)
        fixture.module.startCountdown(minutes: 5)
        #expect(fixture.harness.activities.current?.id == "timer/timer")
        #expect(fixture.harness.activities.current?.activity.priority == .normal)
        let revision = fixture.harness.activities.current
        fixture.advance(120)
        #expect(fixture.harness.activities.current == revision)
    }

    @Test func pauseAndCancelClearTheActivity() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 5)
        fixture.module.pause()
        #expect(fixture.harness.activities.current == nil)
        fixture.module.resume()
        #expect(fixture.harness.activities.current != nil)
        fixture.module.cancel()
        #expect(fixture.harness.activities.current == nil)
        #expect(fixture.harness.scheduler.pendingCount == 0)
    }

    /// "Một lần": the old behaviour, a single sound. The activity stays up for as long as the alert lasts (60 s), so the
    /// pulse and the finish text have something to sit on while the sound repeats.
    @Test func finishingShowsHighActivityPlaysSoundOnceAndExpiresAfterTheAlertWindow() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.setAlert(.once)
        fixture.module.startCountdown(minutes: 1)
        fixture.advance(59)
        #expect(fixture.sound.played.isEmpty)
        fixture.advance(1)
        #expect(fixture.sound.played == ["Glass"])
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.harness.activities.current?.activity.priority == .high)
        fixture.advance(59)
        #expect(fixture.harness.activities.current != nil)
        fixture.advance(1)
        #expect(fixture.harness.activities.current == nil)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.sound.played == ["Glass"])
    }

    @Test func cancellingTheFinishedTimerDismissesIt() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 1)
        fixture.advance(60)
        fixture.module.cancel()
        #expect(fixture.harness.activities.current == nil)
        #expect(fixture.module.state.model == .idle)
    }

    @Test func addMinuteAfterFinishingRestartsTheCountdown() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 1)
        fixture.advance(60)
        fixture.module.addMinute()
        #expect(fixture.harness.activities.current?.activity.priority == .normal)
        fixture.advance(60)
        #expect(fixture.sound.played == ["Glass", "Glass"])
    }

    @Test func sleepingPastTheEndFinishesWhenTheTimerFires() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 5)
        fixture.clock.advance(3_600)
        fixture.harness.scheduler.advance(by: .seconds(300))
        #expect(fixture.module.state.model == .finished)
    }

    @Test func aClockMovedBackWaitsForTheRestOfTheCountdown() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 5)
        // The scheduler ran the full 300 s, but the wall clock only 200 s of them.
        fixture.clock.advance(200)
        fixture.harness.scheduler.advance(by: .seconds(300))
        #expect(fixture.module.state.model == .countdown(endDate: Date(timeIntervalSinceReferenceDate: 1_300)))
        #expect(fixture.sound.played.isEmpty)
        #expect(fixture.harness.scheduler.pendingCount == 1)
        fixture.advance(100)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.sound.played == ["Glass"])
    }

    @Test func stopwatchPublishesAnActivityAndNeverFinishes() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startStopwatch()
        #expect(fixture.harness.activities.current?.id == "timer/timer")
        fixture.advance(10_000)
        #expect(fixture.sound.played.isEmpty)
        #expect(fixture.module.state.model.elapsed(now: fixture.clock.date) == 10_000)
    }

    @Test func everyChangeIsSavedToTimerJson() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 10)
        #expect(try fixture.savedModel() == .countdown(endDate: fixture.clock.date.addingTimeInterval(600)))
        fixture.advance(60)
        fixture.module.pause()
        #expect(try fixture.savedModel() == .countdownPaused(remaining: 540))
        fixture.module.cancel()
        #expect(try fixture.savedModel() == .idle)
    }

    @Test func runningCountdownIsRestoredWithTheRightRemainingTime() async throws {
        let fixture = TimerFixture()
        try fixture.seedFile(.countdown(endDate: fixture.clock.date.addingTimeInterval(400)))
        await fixture.start()
        #expect(fixture.module.state.model.remaining(now: fixture.clock.date) == 400)
        #expect(fixture.harness.activities.current?.activity.priority == .normal)
        fixture.advance(400)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.sound.played == ["Glass"])
    }

    /// Older than the two-minute window: shown, as before, but not announced. `TimerAlertTests` has the two sides of the window.
    @Test func countdownThatFinishedLongBeforeTheAppStartedShowsFinishedWithoutASound() async throws {
        let fixture = TimerFixture()
        try fixture.seedFile(.countdown(endDate: fixture.clock.date.addingTimeInterval(-300)))
        await fixture.start()
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.harness.activities.current?.activity.priority == .high)
        #expect(fixture.harness.activities.current?.activity.expiresAfter == .seconds(30))
        #expect(fixture.sound.played.isEmpty)
        #expect(fixture.harness.presenter.toastCount == 0)
        #expect(try fixture.savedModel() == .finished)
    }

    @Test func aTimerThatWasAlreadyFinishedWhenTheAppClosedIsNotAnnouncedAgain() async throws {
        let fixture = TimerFixture()
        try fixture.seedFile(.finished)
        await fixture.start()
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.harness.activities.current == nil)
        #expect(fixture.sound.played.isEmpty)

        fixture.module.cancel()
        #expect(fixture.module.state.model == .idle)
    }

    @Test func pausedAndStopwatchStatesAreRestored() async throws {
        let paused = TimerFixture()
        try paused.seedFile(.countdownPaused(remaining: 77))
        await paused.start()
        #expect(paused.module.state.model == .countdownPaused(remaining: 77))
        #expect(paused.harness.activities.current == nil)

        let watch = TimerFixture()
        let began = watch.clock.date.addingTimeInterval(-50)
        try watch.seedFile(.stopwatch(accumulated: 10, startedAt: began))
        await watch.start()
        #expect(watch.module.state.model.elapsed(now: watch.clock.date) == 60)
        #expect(watch.harness.activities.current != nil)
    }

    @Test func corruptFileStartsIdle() async throws {
        let fixture = TimerFixture()
        try FileManager.default.createDirectory(at: fixture.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: fixture.fileURL)
        await fixture.start()
        #expect(fixture.harness.registry.state(of: "timer") == .running)
        #expect(fixture.module.state.model == .idle)
    }

    @Test func enablingAgainRestoresARunningCountdownFromTheFile() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 5)
        await fixture.harness.registry.setEnabled(false, for: "timer")
        #expect(fixture.module.state.model == .idle)
        fixture.clock.advance(100)
        await fixture.harness.registry.setEnabled(true, for: "timer")
        #expect(fixture.module.state.model.remaining(now: fixture.clock.date) == 200)
        #expect(fixture.harness.activities.current?.activity.priority == .normal)
        fixture.advance(200)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.sound.played == ["Glass"])
    }

    // MARK: Lock screen

    @Test func aRunningCountdownOffersItsRemainingTimeToTheLockScreen() async {
        let fixture = TimerFixture()
        await fixture.start()
        #expect(fixture.harness.lockScreen.current == nil)
        fixture.module.startCountdown(minutes: 5)
        #expect(fixture.harness.lockScreen.current?.module == "timer")
        #expect(fixture.harness.lockScreen.current?.priority == .high)
    }

    @Test func aStopwatchIsNeverOfferedToTheLockScreen() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startStopwatch()
        #expect(fixture.harness.activities.current?.id == "timer/timer")
        #expect(fixture.harness.lockScreen.current == nil)

        // Replacing a countdown with a stopwatch takes the countdown off.
        fixture.module.startCountdown(minutes: 5)
        #expect(fixture.harness.lockScreen.current != nil)
        fixture.module.startStopwatch()
        #expect(fixture.harness.lockScreen.current == nil)
    }

    /// A finish is not the running time any more: it says "Hết giờ" until the user answers (`TimerAlertTests`).
    @Test func pausingFinishingAndCancellingTakeTheRunningTimeOffTheLockScreen() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 1)
        fixture.module.pause()
        #expect(fixture.harness.lockScreen.current == nil)
        fixture.module.resume()
        #expect(fixture.harness.lockScreen.current != nil)
        fixture.advance(60)
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.harness.lockScreen.current?.priority == .high)   // now the finished text, not the time
        fixture.module.addMinute()
        #expect(fixture.harness.lockScreen.current != nil)
        fixture.module.cancel()
        #expect(fixture.harness.lockScreen.current == nil)
    }

    @Test func aRestoredRunningCountdownIsOnTheLockScreen() async throws {
        let fixture = TimerFixture()
        try fixture.seedFile(.countdown(endDate: fixture.clock.date.addingTimeInterval(400)))
        await fixture.start()
        #expect(fixture.harness.lockScreen.current?.module == "timer")
    }

    @Test func disablingRemovesTheTimeFromTheLockScreen() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 1)
        await fixture.harness.registry.setEnabled(false, for: "timer")
        #expect(fixture.harness.lockScreen.current == nil)
    }

    // MARK: Review follow-ups

    @Test func pausingACountdownThatIsDueFinishesItInsteadOfPausingAtZero() async throws {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.setAlert(.once)
        fixture.module.startCountdown(minutes: 1)
        // The wall clock passed the end (e.g. after sleep) but the finish timer has not run yet.
        fixture.clock.advance(61)
        fixture.module.pause()
        #expect(fixture.module.state.model == .finished)
        #expect(fixture.sound.played == ["Glass"])
        #expect(fixture.harness.activities.current?.activity.priority == .high)
        #expect(try fixture.savedModel() == .finished)

        // The finish timer that was already armed must not announce it a second time.
        fixture.harness.scheduler.advance(by: .seconds(120))
        #expect(fixture.sound.played == ["Glass"])
        #expect(fixture.harness.presenter.toastCount == 1)
    }

    @Test func aChangeToACountdownThatIsStillRunningIsAppliedAsBefore() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 1)
        fixture.advance(30)
        fixture.module.pause()
        #expect(fixture.module.state.model == .countdownPaused(remaining: 30))
        #expect(fixture.sound.played.isEmpty)
    }

    @Test func aMissingFileIsAFirstRunAndACorruptOneIsReported() throws {
        let fixture = TimerFixture()
        let missing = TimerModule.load(from: fixture.fileURL)
        #expect(missing.model == .idle)
        #expect(missing.error == nil)

        try FileManager.default.createDirectory(at: fixture.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: fixture.fileURL)
        let corrupt = TimerModule.load(from: fixture.fileURL)
        #expect(corrupt.model == .idle)
        #expect(corrupt.error != nil)

        try fixture.seedFile(.countdownPaused(remaining: 12))
        let valid = TimerModule.load(from: fixture.fileURL)
        #expect(valid.model == .countdownPaused(remaining: 12))
        #expect(valid.error == nil)
    }

    @Test func theTabAndTheLockScreenCountDownFromTheSameFixedRange() {
        let end = Date(timeIntervalSinceReferenceDate: 5_000)
        let range = TimerTabView.countdownRange(to: end)
        #expect(range.upperBound == end)
        #expect(range.lowerBound == .distantPast)
        #expect(TimerLockScreenView(endDate: end).range == range)
    }

    @Test func disablingStopsTheTimerAndRemovesTheActivity() async {
        let fixture = TimerFixture()
        await fixture.start()
        fixture.module.startCountdown(minutes: 1)
        await fixture.harness.registry.setEnabled(false, for: "timer")
        #expect(fixture.harness.activities.current == nil)
        fixture.advance(120)
        #expect(fixture.sound.played.isEmpty)
    }
}
