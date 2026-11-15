import MyNotchCore

/// Which kinds of media key the HUD takes over, from the three sub-toggles in Settings.
nonisolated struct MediaKeySelection: Equatable, Sendable {
    var volume = true
    var brightness = true
    var keyboardLight = true

    func contains(_ target: MediaKey.Target) -> Bool {
        switch target {
        case .volume: volume
        case .brightness: brightness
        case .keyboardLight: keyboardLight
        }
    }
}

/// Takes over the volume, brightness and keyboard light keys: swallows them, makes the change itself and reports it
/// as an activity, so MyNotch's bar shows instead of the macOS one.
///
/// The tap callback runs on the main thread and holds up every system-defined event of the session while it works,
/// so it only decides: whether to swallow a key comes from the sub-toggles and from what the last look at the
/// hardware found, and the change itself is made later on the hardware queue. A key whose control is missing (no
/// built-in display, no backlit keyboard, a private framework that changed) is therefore not swallowed, and one that
/// fails after all gives its kind back to the system from the next press on; the press that found out is lost.
///
/// Without Accessibility there is no tap at all, so every key stays the system's; the HUD asks again every 2 s, which
/// is how it notices the permission being granted. A tap that is up is checked every 10 s, because macOS does not
/// always say when it switches one off.
final class MediaKeyHUD {
    /// How long the bar stays after the last key press.
    static let displayDuration: Duration = .milliseconds(1_500)
    static let retryInterval: Duration = .seconds(2)
    /// How often a tap that is up is checked, and what the keys can do is looked at again.
    static let checkInterval: Duration = .seconds(10)

    private let tap: any EventTapping
    private let queue: any HardwareQueue
    private let changes: any HardwareChangeSource
    private let hardware: MediaKeyHardware
    private let isTrusted: () -> Bool
    private let scheduler: any Scheduler
    private var enabled: (() -> MediaKeySelection)?
    private var onChange: (@MainActor (SystemActivityContent) -> Void)?
    /// The wait for the permission, or the next check of the tap.
    private var timer: ScheduledAction?
    /// What the keys can do. Nothing until the first look at the hardware returns, so until then they stay the system's.
    private var availability = MediaKeyAvailability()
    /// Whether each key that is down was swallowed, so its repeats and its release go the way its press went.
    private var held: [MediaKey: Bool] = [:]
    /// Tells the answers of the hardware queue that belong to an earlier run from this run's.
    private var run = 0
    /// The volume this HUD set last, which the volume monitor reports back a moment later.
    private var lastVolume: VolumeState?

    init(
        tap: any EventTapping, queue: any HardwareQueue, changes: any HardwareChangeSource,
        volume: any VolumeControlling, brightness: any LevelControlling, keyboardLight: any LevelControlling,
        isTrusted: @escaping () -> Bool, scheduler: any Scheduler
    ) {
        self.tap = tap
        self.queue = queue
        self.changes = changes
        hardware = MediaKeyHardware(volume: volume, brightness: brightness, keyboardLight: keyboardLight)
        self.isTrusted = isTrusted
        self.scheduler = scheduler
    }

    /// `enabled` is read at every key press, so a sub-toggle takes effect at once. Starting again replaces the run.
    func start(enabled: @escaping () -> MediaKeySelection, onChange: @escaping @MainActor (SystemActivityContent) -> Void) {
        stop()
        self.enabled = enabled
        self.onChange = onChange
        attach()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        detach()
        run += 1
        availability = MediaKeyAvailability()
        enabled = nil
        onChange = nil
        lastVolume = nil
    }

    /// Whether `state` is the volume this HUD just set, which the volume monitor reports back. Any other volume is
    /// somebody else's change and makes the HUD forget its own.
    func isEcho(_ state: VolumeState) -> Bool {
        guard state == lastVolume else {
            lastVolume = nil
            return false
        }
        return true
    }

    // MARK: tap

    /// Without Accessibility macOS refuses the tap, so it is not even attempted; either way it is tried again later.
    /// With the tap up, the HUD starts to look at the hardware and checks the tap from time to time.
    private func attach() {
        timer?.cancel()
        timer = nil
        if isTrusted(), tap.install({ [weak self] in self?.receive($0) ?? false }) {
            held = [:]
            changes.start { [weak self] in self?.look() }
            look()
            timer = scheduler.schedule(after: Self.checkInterval) { [weak self] in self?.check() }
        } else {
            timer = scheduler.schedule(after: Self.retryInterval) { [weak self] in self?.attach() }
        }
    }

    private func detach() {
        tap.uninstall()
        changes.stop()
        held = [:]
    }

    /// With Accessibility gone, switching a tap back on would not help: wait for the permission instead.
    private func lose() {
        detach()
        attach()
    }

    private func check() {
        guard isTrusted() else { return lose() }
        if !tap.isAlive { tap.reenable() }
        guard tap.isAlive else { return lose() }
        look()
        timer = scheduler.schedule(after: Self.checkInterval) { [weak self] in self?.check() }
    }

    private func receive(_ input: EventTapInput) -> Bool {
        switch input {
        case .disabled:
            if isTrusted() { tap.reenable() } else { lose() }
            return false
        case .systemDefined(let subtype, let data1, let modifiers):
            guard let event = MediaKeyEvent(subtype: subtype, data1: data1, modifiers: modifiers) else { return false }
            return handle(event)
        }
    }

    // MARK: keys

    /// True when the event is swallowed. A press is decided here, from what is known already; the repeats of a held
    /// key and its release follow that decision, so the system never sees half a key stroke.
    private func handle(_ event: MediaKeyEvent) -> Bool {
        let key = event.key
        guard event.isDown else { return held.removeValue(forKey: key) ?? false }
        let swallow = (event.isRepeat ? held[key] : nil) ?? decide(key)
        held[key] = swallow
        if swallow { perform(event) }
        return swallow
    }

    private func decide(_ key: MediaKey) -> Bool {
        enabled?().contains(key.target) == true && availability.allows(key)
    }

    /// The change itself is made on the hardware queue, and shown when it comes back.
    private func perform(_ event: MediaKeyEvent) {
        let hardware = hardware
        let key = event.key
        let steps = LevelStep.steps(fine: event.isFine)
        let run = run
        queue.run({ hardware.perform(key, steps: steps) }, then: { [weak self] outcome in
            guard let self, self.run == run else { return }
            finish(outcome)
        })
    }

    private func finish(_ outcome: MediaKeyOutcome) {
        switch outcome {
        case .volume(let state):
            lastVolume = state
            onChange?(.volume(state))
        case .brightness(let level): onChange?(.brightness(level))
        case .keyboardLight(let level): onChange?(.keyboardLight(level))
        // Looking again right now would find a control that reads but does not write working: the next look, on a
        // change or with the check, decides.
        case .failed(let target): availability.lose(target)
        }
    }

    /// Looks at which controls work now, off the main thread.
    private func look() {
        let hardware = hardware
        let run = run
        queue.run({ hardware.probe() }, then: { [weak self] found in
            guard let self, self.run == run else { return }
            availability = found
        })
    }
}
