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
    /// How long the finished activity stays up when nobody was told (a finish long before launch).
    static let finishedLifetime = Duration.seconds(30)
    /// How long an announced finish asks for attention: the repeating sound's cap, the toast and the finished activity.
    static let alertLifetime = Duration.seconds(60)
    /// Time between two sounds of "Lặp đến khi tắt".
    static let repeatInterval = Duration.seconds(3)
    /// What "+5 phút" on the toast restarts the countdown for.
    static let snoozeMinutes = 5
    /// A countdown that ended less than this long before launch is still announced.
    static let catchUpWindow: TimeInterval = 120

    let state = TimerState()
    private let now: () -> Date
    private let sound: any SoundPlaying
    private var context: ModuleContext?
    private var fileURL: URL?
    private var finishTimer: ScheduledAction?
    /// The next sound of a repeating alert, and how many have played.
    private var repeatTimer: ScheduledAction?
    private var soundsPlayed = 0
    /// Sees each finish line that is logged, so a test can check what it says; the logger itself cannot be read back.
    var logObserver: ((String) -> Void)?

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
        state.model = stored
        state.session = session
        // Finished while the app was closed: announced if it was only just now, otherwise shown and left at that.
        let lateness = refreshFinished(now: now(), logger: context.logger)
        self.context = context
        fileURL = url
        // One that was already finished at the last quit stays in the tab but is not raised again on every launch.
        commit(finishedLateBy: lateness.flatMap { $0 < Self.catchUpWindow ? $0 : nil }, publishes: stored != .finished)
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
        stopAlert()
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

    // MARK: The end of a countdown

    /// What the toast says and offers: the next step where the type has one, "+5 phút" and "Tắt". Each button closes the notch
    /// after it, since the toast was what the notch was showing.
    var finishToast: TimerFinishToast {
        var actions: [TimerFinishAction] = []
        if let suggestion {
            actions.append(TimerFinishAction(role: .next, title: suggestion.toastTitle) { [weak self] in
                self?.startNext()
                self?.context?.presenter.close()
            })
        }
        actions.append(TimerFinishAction(role: .snooze, title: "+\(Self.snoozeMinutes) phút") { [weak self] in
            self?.snooze()
            self?.context?.presenter.close()
        })
        actions.append(TimerFinishAction(role: .dismiss, title: "Tắt") { [weak self] in
            self?.dismissFinished()
            self?.context?.presenter.close()
        })
        return TimerFinishToast(session: state.session, actions: actions)
    }

    /// Restarts the finished countdown, same type and label, for `snoozeMinutes`. Nothing happens once it is no longer finished.
    func snooze() {
        guard state.model == .finished else { return }
        startCountdown(minutes: Self.snoozeMinutes, kind: state.session.kind, label: state.session.label)
    }

    /// Dismisses the finished timer, and only that: a button of a toast that outlived it must not cancel what was started since.
    func dismissFinished() {
        guard state.model == .finished else { return }
        cancel()
    }

    /// The Timer tab came on screen: the user has seen the timer, so the sound, the pulse and the lock screen stand down. The
    /// finished timer stays in the tab until it is dismissed.
    func acknowledgeFinish() {
        guard state.isAlerting else { return }
        stopAlert()
        context?.lockScreen.clear()
    }

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

    /// A countdown that is already due finishes first, so pausing it (or any other change) cannot freeze it at zero. It is
    /// announced only if the change leaves it finished: cancelling or replacing one that is overdue is the user's answer already.
    /// Starting one sets its type, and the dial of that type goes back to its default for the next time.
    private func mutate(starting session: TimerSession? = nil, _ change: (inout TimerModel, Date) -> Void) {
        guard let context else { return }
        let now = now()
        let lateness = refreshFinished(now: now, logger: context.logger)
        if let session {
            state.session = session
            state.adjustedMinutes[session.kind] = nil
        }
        change(&state.model, now)
        commit(finishedLateBy: lateness)
    }

    /// Turns a countdown that is due into `.finished` and logs it: its type and how late it is, never its label. Returns how
    /// many seconds past its end it is, or nil if nothing finished.
    private func refreshFinished(now: Date, logger: Logger) -> TimeInterval? {
        guard case .countdown(let endDate) = state.model, state.model.refresh(now: now) else { return nil }
        let lateness = max(0, now.timeIntervalSince(endDate))
        let line = Self.finishLogMessage(kind: state.session.kind, lateness: lateness)
        logger.debug("\(line, privacy: .public)")
        logObserver?(line)
        return lateness
    }

    static func finishLogMessage(kind: TimerKind, lateness: TimeInterval) -> String {
        "Countdown finished: type=\(kind.rawValue) late=\(Int(lateness.rounded()))s"
    }

    /// Saves the state, announces a countdown that has just ended (`finishedLateBy`), publishes the matching activity and arms
    /// the finish timer. Whatever leaves `.finished` ends the alert, so every answer of the user is covered here.
    private func commit(finishedLateBy lateness: TimeInterval? = nil, publishes: Bool = true) {
        guard let context else { return }
        if state.model != .finished {
            stopAlert()
        } else if lateness != nil {
            announceFinish(in: context)
        }
        save(logger: context.logger)
        if publishes || state.model != .finished { publish(in: context) }
        scheduleFinish(on: context.scheduler)
    }

    // MARK: The alert

    /// Raises the alert: the toast, the sound as the setting says, the pulse and the lock screen text (the last two read
    /// `isAlerting`, which `publish` follows).
    private func announceFinish(in context: ModuleContext) {
        state.isAlerting = true
        startSound(in: context)
        context.presenter.showToast(AnyView(TimerFinishToastView(toast: finishToast)), duration: Self.alertLifetime)
    }

    /// Ends the alert: the sound that is playing and the ones to come stop, and the pulse with them. A no-op when none is up.
    private func stopAlert() {
        guard state.isAlerting else { return }
        state.isAlerting = false
        repeatTimer?.cancel()
        repeatTimer = nil
        sound.stop()
    }

    private func startSound(in context: ModuleContext) {
        soundsPlayed = 0
        switch context.settings.value(TimerSettingsKeys(context.settings).alertMode) {
        case .off: break
        case .once: playSound(in: context)
        case .repeating: playRepeating(in: context)
        }
    }

    private func playSound(in context: ModuleContext) {
        sound.play(named: TimerAlertSound.resolved(context.settings.value(TimerSettingsKeys(context.settings).alertSound)))
        soundsPlayed += 1
    }

    /// One sound now and one every `repeatInterval` until `alertLifetime` is used up (twenty in all).
    private func playRepeating(in context: ModuleContext) {
        playSound(in: context)
        guard Self.repeatInterval * soundsPlayed < Self.alertLifetime else {
            repeatTimer = nil
            return
        }
        repeatTimer = context.scheduler.schedule(after: Self.repeatInterval) { [weak self] in
            guard let self, state.isAlerting, let context = self.context else { return }
            playRepeating(in: context)
        }
    }

    private func save(logger: Logger) {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(StoredTimer(model: state.model, session: state.session)).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save the timer: \(error.localizedDescription)")
        }
    }

    /// The lock screen shows the remaining time of a running countdown, and "Hết giờ · ..." while a finish waits for an answer;
    /// everything else leaves it.
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
            let lifetime = state.isAlerting ? Self.alertLifetime : Self.finishedLifetime
            context.activities.set(TimerActivity.finished(session: state.session, state: state, expiresAfter: lifetime))
            if state.isAlerting {
                context.lockScreen.set(AnyView(TimerFinishedLockScreenView(session: state.session)), priority: .high)
            } else {
                context.lockScreen.clear()
            }
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
        guard let context else { return }
        if let lateness = refreshFinished(now: now(), logger: context.logger) {
            commit(finishedLateBy: lateness)
        } else {
            scheduleFinish(on: context.scheduler)   // the clock moved back: wait for the rest
        }
    }
}
