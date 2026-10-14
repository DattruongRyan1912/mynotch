import MyNotchCore
import NotchUI
import SwiftUI
import os

/// Focus, reminder and break timers set with a minute dial, and a stopwatch. The state lives in `timer.json`, so a timer
/// keeps running across relaunch.
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
        let (stored, session, loadError) = Self.load(from: url)
        if let loadError {
            context.logger.error("Could not read timer.json, starting idle: \(loadError.localizedDescription)")
        }
        var model = stored
        _ = model.refresh(now: now())   // finished while the app was closed: shown, but not announced with a sound
        self.context = context
        fileURL = url
        state.model = model
        state.session = session
        // One that was already finished at the last quit stays in the tab but is not raised again on every launch.
        commit(announcesFinish: stored != .finished)
    }

    /// A missing file is a first run: idle, no error. Any other failure is returned with the idle state, to be logged.
    static func load(from url: URL) -> (model: TimerModel, session: TimerSession, error: (any Error)?) {
        do {
            let stored = try JSONDecoder().decode(StoredTimer.self, from: Data(contentsOf: url))
            return (stored.model, stored.session, nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return (.idle, .plain, nil)
        } catch {
            return (.idle, .plain, error)
        }
    }

    public func stop() async {
        finishTimer?.cancel()
        finishTimer = nil
        context = nil
        fileURL = nil
        state.model = .idle
        state.session = .plain
        state.adjustedMinutes = [:]
    }

    /// Takes the keyboard (the dial answers the arrow keys and the reminder has a text field).
    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Hẹn giờ", systemImage: "timer", preferredHeight: TimerTabView.preferredHeight,
            acceptsKeyboard: true, content: AnyView(TimerTabView(state: state, module: self)))
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(TimerSettingsView(settings: environment.settings, keys: TimerSettingsKeys(environment.settings)))
    }

    /// A countdown of zero minutes would end before it began, so it is not started. Without a type it is the old quick
    /// timer: a reminder with no label.
    func startCountdown(minutes: Int, kind: TimerKind = .reminder, label: String = "") {
        guard minutes > 0 else { return }
        mutate(starting: TimerSession(kind: kind, label: label)) { $0.startCountdown(minutes: minutes, now: $1) }
    }

    /// What "Bắt đầu", a quick length and Return in the reminder field do: a reminder takes the label typed so far and
    /// empties the field for the next one. At 0 minutes nothing starts, and the label stays.
    func startFromTab(_ kind: TimerKind, minutes: Int) {
        guard minutes > 0 else { return }
        startCountdown(minutes: minutes, kind: kind, label: state.reminderLabel)
        if kind == .reminder { state.reminderLabel = "" }
    }

    func startStopwatch() { mutate { $0.startStopwatch(now: $1) } }
    func pause() { mutate { $0.pause(now: $1) } }
    func resume() { mutate { $0.resume(now: $1) } }
    func addMinute() { mutate { $0.addMinute(now: $1) } }
    /// Also dismisses a finished timer.
    func cancel() { mutate { model, _ in model.cancel() } }

    // MARK: Types and the dial

    /// What to offer once the timer on screen has ended: a break after a task and a task after a break.
    var suggestion: TimerSuggestion? {
        guard state.model == .finished, let next = state.session.kind.next else { return nil }
        return TimerSuggestion(kind: next, minutes: defaultMinutes(for: next))
    }

    /// Starts what `suggestion` offers.
    func startNext() {
        guard let suggestion else { return }
        startCountdown(minutes: suggestion.minutes, kind: suggestion.kind)
    }

    /// The length the user chose for the type in Settings.
    func defaultMinutes(for kind: TimerKind) -> Int {
        guard let context else { return kind.defaultMinutes }
        return context.settings.value(TimerSettingsKeys(context.settings).key(for: kind))
    }

    /// What the dial shows for the type: where it was turned to, else the Settings default.
    func minutes(for kind: TimerKind) -> Int {
        state.adjustedMinutes[kind] ?? defaultMinutes(for: kind)
    }

    func setMinutes(_ minutes: Int, for kind: TimerKind) {
        state.adjustedMinutes[kind] = MinuteDial.clamped(minutes)
    }

    /// A countdown that is already due finishes first, so pausing it (or any other change) cannot freeze it at zero.
    /// Starting one sets its type, and the dial of that type goes back to its default for the next time.
    private func mutate(starting session: TimerSession? = nil, _ change: (inout TimerModel, Date) -> Void) {
        guard context != nil else { return }
        let now = now()
        if state.model.refresh(now: now) { sound.play(named: Self.finishedSound) }
        if let session {
            state.session = session
            state.adjustedMinutes[session.kind] = nil
        }
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
            try JSONEncoder().encode(StoredTimer(model: state.model, session: state.session)).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save the timer: \(error.localizedDescription)")
        }
    }

    /// The lock screen shows only the remaining time of a running countdown; everything else leaves it.
    private func publish(in context: ModuleContext) {
        let now = now()
        switch state.model {
        case .countdown(let endDate):
            context.activities.set(TimerActivity.running(session: state.session, range: now...max(endDate, now)))
            context.lockScreen.set(AnyView(TimerLockScreenView(endDate: endDate, session: state.session)), priority: .high)
        case .stopwatch(let accumulated, let startedAt):
            context.activities.set(TimerActivity.stopwatch(range: startedAt.addingTimeInterval(-accumulated)...Date.distantFuture))
            context.lockScreen.clear()
        case .finished:
            context.activities.set(TimerActivity.finished(session: state.session, expiresAfter: Self.finishedLifetime))
            context.lockScreen.clear()
        case .idle, .countdownPaused, .stopwatchPaused:
            context.activities.clear(id: Self.activityID)
            context.lockScreen.clear()
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
