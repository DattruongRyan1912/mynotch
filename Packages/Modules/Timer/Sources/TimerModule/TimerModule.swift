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
        var model = (try? JSONDecoder().decode(TimerModel.self, from: Data(contentsOf: url))) ?? .idle
        _ = model.refresh(now: now())   // finished while the app was closed: shown, but not announced with a sound
        self.context = context
        fileURL = url
        state.model = model
        commit()
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

    private func mutate(_ change: (inout TimerModel, Date) -> Void) {
        guard context != nil else { return }
        change(&state.model, now())
        commit()
    }

    /// Saves the state, publishes the matching activity and arms the finish timer.
    private func commit() {
        guard let context else { return }
        save(logger: context.logger)
        publish(to: context.activities)
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

    private func publish(to activities: ActivityPublisher) {
        let now = now()
        switch state.model {
        case .countdown(let endDate):
            activities.set(TimerActivity.running(
                systemImage: "hourglass", range: now...max(endDate, now), countsDown: true))
        case .stopwatch(let accumulated, let startedAt):
            activities.set(TimerActivity.running(
                systemImage: "stopwatch", range: startedAt.addingTimeInterval(-accumulated)...Date.distantFuture, countsDown: false))
        case .finished:
            activities.set(TimerActivity.finished(expiresAfter: Self.finishedLifetime))
        case .idle, .countdownPaused, .stopwatchPaused:
            activities.clear(id: Self.activityID)
        }
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
