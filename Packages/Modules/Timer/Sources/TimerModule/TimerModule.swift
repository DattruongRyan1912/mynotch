import MyNotchCore
import NotchUI
import SwiftUI
import os

/// Countdown timer and stopwatch. The state lives in `timer.json`, so a timer keeps running across relaunch.
public final class TimerModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "timer",
        displayName: "Hẹn giờ",
        systemImage: "timer",
        defaultEnabled: true,
        order: 880
    )

    static let activityID = "timer"
    static let finishedSound = "Glass"
    static let finishedLifetime = Duration.seconds(30)

    let state = TimerState()
    private let now: () -> Date
    private let sound: any SoundPlaying
    private var context: ModuleContext?
    private var fileURL: URL?
    private var finishTimer: ScheduledAction?

    init(now: @escaping () -> Date, sound: any SoundPlaying) {
        self.now = now
        self.sound = sound
    }

    public convenience init() { self.init(now: { .now }, sound: SystemSoundPlayer()) }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        do {
            try context.storage.ensureDirectories()
        } catch {
            throw .failed(reason: "Không tạo được thư mục lưu hẹn giờ")
        }
        let url = context.storage.directory.appending(path: "timer.json")
        let (stored, loadError) = Self.load(from: url)
        if let loadError {
            context.logger.error("Could not read timer.json, starting idle: \(loadError.localizedDescription)")
        }
        var model = stored
        _ = model.refresh(now: now())   // finished while the app was closed: shown, but not announced with a sound
        self.context = context
        fileURL = url
        state.model = model
        // One that was already finished at the last quit stays in the tab but is not raised again on every launch.
        commit(announcesFinish: stored != .finished)
    }

    /// A missing file is a first run: idle, no error. Any other failure is returned with the idle state, to be logged.
    static func load(from url: URL) -> (model: TimerModel, error: (any Error)?) {
        do {
            return (try JSONDecoder().decode(TimerModel.self, from: Data(contentsOf: url)), nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return (.idle, nil)
        } catch {
            return (.idle, error)
        }
    }

    public func stop() async {
        finishTimer?.cancel()
        finishTimer = nil
        context = nil
        fileURL = nil
        state.model = .idle
    }

    public func makeTab() -> NotchTab? {
        NotchTab(id: descriptor.id, title: "Hẹn giờ", systemImage: "timer", preferredHeight: 150, content: AnyView(TimerTabView(state: state, module: self)))
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }

    func startCountdown(minutes: Int) { mutate { $0.startCountdown(minutes: minutes, now: $1) } }
    func startStopwatch() { mutate { $0.startStopwatch(now: $1) } }
    func pause() { mutate { $0.pause(now: $1) } }
    func resume() { mutate { $0.resume(now: $1) } }
    func addMinute() { mutate { $0.addMinute(now: $1) } }
    /// Also dismisses a finished timer.
    func cancel() { mutate { model, _ in model.cancel() } }

    /// A countdown that is already due finishes first, so pausing it (or any other change) cannot freeze it at zero.
    private func mutate(_ change: (inout TimerModel, Date) -> Void) {
        guard context != nil else { return }
        let now = now()
        if state.model.refresh(now: now) { sound.play(named: Self.finishedSound) }
        change(&state.model, now)
        commit()
    }

    /// Saves the state, publishes the matching activity and arms the finish timer.
    private func commit(announcesFinish: Bool = true) {
        guard let context else { return }
        save(logger: context.logger)
        if announcesFinish || state.model != .finished { publish(in: context) }
        scheduleFinish(on: context.scheduler)
    }

    private func save(logger: Logger) {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(state.model).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save the timer: \(error.localizedDescription)")
        }
    }

    /// The lock screen shows only a running time; finished, paused and idle timers leave it.
    private func publish(in context: ModuleContext) {
        let now = now()
        switch state.model {
        case .countdown(let endDate):
            publishRunning(systemImage: "hourglass", range: now...max(endDate, now), countsDown: true, in: context)
        case .stopwatch(let accumulated, let startedAt):
            publishRunning(
                systemImage: "stopwatch", range: startedAt.addingTimeInterval(-accumulated)...Date.distantFuture, countsDown: false, in: context)
        case .finished:
            context.activities.set(TimerActivity.finished(expiresAfter: Self.finishedLifetime))
            context.lockScreen.clear()
        case .idle, .countdownPaused, .stopwatchPaused:
            context.activities.clear(id: Self.activityID)
            context.lockScreen.clear()
        }
    }

    private func publishRunning(systemImage: String, range: ClosedRange<Date>, countsDown: Bool, in context: ModuleContext) {
        context.activities.set(TimerActivity.running(systemImage: systemImage, range: range, countsDown: countsDown))
        context.lockScreen.set(
            AnyView(TimerLockScreenView(systemImage: systemImage, range: range, countsDown: countsDown)), priority: .high)
    }

    private func scheduleFinish(on scheduler: any Scheduler) {
        finishTimer?.cancel()
        finishTimer = nil
        guard case .countdown(let endDate) = state.model else { return }
        finishTimer = scheduler.schedule(after: .seconds(max(0, endDate.timeIntervalSince(now())))) { [weak self] in
            self?.finishTimerFired()
        }
    }

    private func finishTimerFired() {
        if state.model.refresh(now: now()) {
            sound.play(named: Self.finishedSound)
            commit()
        } else if let context {
            scheduleFinish(on: context.scheduler)   // the clock moved back: wait for the rest
        }
    }
}
