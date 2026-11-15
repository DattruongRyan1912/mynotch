/// Which kinds of media key have something to control now, as the last look at the hardware found it.
nonisolated struct MediaKeyAvailability: Equatable, Sendable {
    var volume = false
    /// The output device can be muted.
    var mute = false
    var brightness = false
    var keyboardLight = false

    func allows(_ key: MediaKey) -> Bool {
        switch key {
        case .volumeUp, .volumeDown: volume
        case .mute: volume && mute
        case .brightnessUp, .brightnessDown: brightness
        case .keyboardLightUp, .keyboardLightDown, .keyboardLightToggle: keyboardLight
        }
    }

    /// Gives a kind back to the system until the next look finds its control working again.
    mutating func lose(_ target: MediaKey.Target) {
        switch target {
        case .volume: (volume, mute) = (false, false)
        case .brightness: brightness = false
        case .keyboardLight: keyboardLight = false
        }
    }
}

/// What a key press did to the hardware, for the HUD to show.
nonisolated enum MediaKeyOutcome: Equatable, Sendable {
    case volume(VolumeState)
    case brightness(Float)
    case keyboardLight(Float)
    /// The control could not be read or did not take the change, so nothing was done.
    case failed(MediaKey.Target)
}

/// What the HUD does to the volume, the display and the keyboard light, and the look at which of them are there.
///
/// Every call can wait on CoreAudio, DisplayServices or CoreBrightness, so they run on the `HardwareQueue` and
/// nowhere else, one after the other; that is why the class can be shared with the queue's closures.
nonisolated final class MediaKeyHardware: @unchecked Sendable {
    private let volume: any VolumeControlling
    private let brightness: any LevelControlling
    private let keyboardLight: any LevelControlling
    /// The keyboard light's level before the toggle key switched it off, for switching it back on.
    private var lightBeforeToggle: Float?

    init(volume: any VolumeControlling, brightness: any LevelControlling, keyboardLight: any LevelControlling) {
        self.volume = volume
        self.brightness = brightness
        self.keyboardLight = keyboardLight
    }

    /// Looks at the hardware afresh: forgets the display and the keyboard found before, and sees which controls work.
    func probe() -> MediaKeyAvailability {
        brightness.refresh()
        keyboardLight.refresh()
        let hasVolume = volume.read() != nil
        return MediaKeyAvailability(
            volume: hasVolume, mute: hasVolume && volume.canMute, brightness: brightness.read() != nil,
            keyboardLight: keyboardLight.read() != nil)
    }

    func perform(_ key: MediaKey, steps: Int) -> MediaKeyOutcome {
        let outcome: MediaKeyOutcome? = switch key {
        case .volumeUp: moveVolume(up: true, steps: steps)
        case .volumeDown: moveVolume(up: false, steps: steps)
        case .mute: toggleMute()
        case .brightnessUp: move(brightness, up: true, steps: steps).map { .brightness($0) }
        case .brightnessDown: move(brightness, up: false, steps: steps).map { .brightness($0) }
        case .keyboardLightUp: move(keyboardLight, up: true, steps: steps).map { .keyboardLight($0) }
        case .keyboardLightDown: move(keyboardLight, up: false, steps: steps).map { .keyboardLight($0) }
        case .keyboardLightToggle: toggleKeyboardLight().map { .keyboardLight($0) }
        }
        return outcome ?? .failed(key.target)
    }

    /// A volume key while muted unmutes, like the system's own.
    private func moveVolume(up: Bool, steps: Int) -> MediaKeyOutcome? {
        guard let current = volume.read() else { return nil }
        let level = LevelStep.moved(current.level, up: up, steps: steps)
        guard volume.setLevel(level) else { return nil }
        let stillMuted = current.muted && !volume.setMuted(false)
        return .volume(VolumeState(level: level, muted: stillMuted))
    }

    private func toggleMute() -> MediaKeyOutcome? {
        guard let current = volume.read(), volume.setMuted(!current.muted) else { return nil }
        return .volume(VolumeState(level: current.level, muted: !current.muted))
    }

    /// The level it was set to, nil when it could not be read or did not take.
    private func move(_ control: any LevelControlling, up: Bool, steps: Int) -> Float? {
        guard let current = control.read() else { return nil }
        let level = LevelStep.moved(current, up: up, steps: steps)
        return control.write(level) ? level : nil
    }

    private func toggleKeyboardLight() -> Float? {
        guard let current = keyboardLight.read() else { return nil }
        let level: Float
        if current > 0 {
            lightBeforeToggle = current
            level = 0
        } else {
            level = lightBeforeToggle ?? 1
        }
        return keyboardLight.write(level) ? level : nil
    }
}
