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
/// Every control sits behind a protocol, and a key whose control is missing (no built-in display, no backlit keyboard,
/// a private framework that changed) is never swallowed. Without Accessibility there is no tap at all, so every key
/// stays the system's; the HUD asks again every 2 s, which is how it notices the permission being granted.
final class MediaKeyHUD {
    /// How long the bar stays after the last key press.
    static let displayDuration: Duration = .milliseconds(1_500)
    static let retryInterval: Duration = .seconds(2)

    private let tap: any EventTapping
    private let volume: any VolumeControlling
    private let brightness: any LevelControlling
    private let keyboardLight: any LevelControlling
    private let isTrusted: () -> Bool
    private let scheduler: any Scheduler
    private var enabled: (() -> MediaKeySelection)?
    private var onChange: (@MainActor (SystemActivityContent) -> Void)?
    private var retry: ScheduledAction?
    /// The volume this HUD set last, which the volume monitor reports back a moment later.
    private var lastVolume: VolumeState?
    /// The keyboard light's level before the toggle key switched it off, for switching it back on.
    private var lightBeforeToggle: Float?

    init(
        tap: any EventTapping, volume: any VolumeControlling, brightness: any LevelControlling,
        keyboardLight: any LevelControlling, isTrusted: @escaping () -> Bool, scheduler: any Scheduler
    ) {
        self.tap = tap
        self.volume = volume
        self.brightness = brightness
        self.keyboardLight = keyboardLight
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
        retry?.cancel()
        retry = nil
        tap.uninstall()
        enabled = nil
        onChange = nil
        lastVolume = nil
        lightBeforeToggle = nil
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
    private func attach() {
        retry?.cancel()
        retry = nil
        if isTrusted(), tap.install({ [weak self] in self?.receive($0) ?? false }) { return }
        retry = scheduler.schedule(after: Self.retryInterval) { [weak self] in self?.attach() }
    }

    private func receive(_ input: EventTapInput) -> Bool {
        switch input {
        case .disabled:
            // With Accessibility gone, switching it back on would not help: wait for the permission instead.
            if isTrusted() {
                tap.reenable()
            } else {
                tap.uninstall()
                attach()
            }
            return false
        case .systemDefined(let subtype, let data1, let modifiers):
            guard let event = MediaKeyEvent(subtype: subtype, data1: data1, modifiers: modifiers) else { return false }
            return handle(event)
        }
    }

    // MARK: keys

    /// True when the event is swallowed: its kind is switched on and its control is there. The release of a key is
    /// swallowed like its press, so the system never sees half a key stroke.
    private func handle(_ event: MediaKeyEvent) -> Bool {
        guard enabled?().contains(event.key.target) == true, isAvailable(event.key) else { return false }
        guard event.isDown else { return true }
        let steps = LevelStep.steps(fine: event.isFine)
        switch event.key {
        case .volumeUp: moveVolume(up: true, steps: steps)
        case .volumeDown: moveVolume(up: false, steps: steps)
        case .mute: toggleMute()
        case .brightnessUp: move(brightness, up: true, steps: steps, show: SystemActivityContent.brightness)
        case .brightnessDown: move(brightness, up: false, steps: steps, show: SystemActivityContent.brightness)
        case .keyboardLightUp: move(keyboardLight, up: true, steps: steps, show: SystemActivityContent.keyboardLight)
        case .keyboardLightDown: move(keyboardLight, up: false, steps: steps, show: SystemActivityContent.keyboardLight)
        case .keyboardLightToggle: toggleKeyboardLight()
        }
        return true
    }

    private func isAvailable(_ key: MediaKey) -> Bool {
        switch key.target {
        case .volume: volume.read() != nil && (key != .mute || volume.canMute)
        case .brightness: brightness.read() != nil
        case .keyboardLight: keyboardLight.read() != nil
        }
    }

    /// A volume key while muted unmutes, like the system's own.
    private func moveVolume(up: Bool, steps: Int) {
        guard let current = volume.read() else { return }
        let level = LevelStep.moved(current.level, up: up, steps: steps)
        guard volume.setLevel(level) else { return }
        let stillMuted = current.muted && !volume.setMuted(false)
        showVolume(VolumeState(level: level, muted: stillMuted))
    }

    private func toggleMute() {
        guard let current = volume.read(), volume.setMuted(!current.muted) else { return }
        showVolume(VolumeState(level: current.level, muted: !current.muted))
    }

    private func showVolume(_ state: VolumeState) {
        lastVolume = state
        onChange?(.volume(state))
    }

    private func move(_ control: any LevelControlling, up: Bool, steps: Int, show: (Float) -> SystemActivityContent) {
        guard let current = control.read() else { return }
        let level = LevelStep.moved(current, up: up, steps: steps)
        if control.write(level) { onChange?(show(level)) }
    }

    private func toggleKeyboardLight() {
        guard let current = keyboardLight.read() else { return }
        let level: Float
        if current > 0 {
            lightBeforeToggle = current
            level = 0
        } else {
            level = lightBeforeToggle ?? 1
        }
        if keyboardLight.write(level) { onChange?(.keyboardLight(level)) }
    }
}
