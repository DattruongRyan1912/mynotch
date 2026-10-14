import AppKit
import IOKit.hidsystem

/// A media key the HUD can take over. Play, next and previous are not here: they belong to the Media module.
nonisolated enum MediaKey: Equatable, Sendable {
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
    case keyboardLightUp, keyboardLightDown, keyboardLightToggle

    /// What the key changes, which the sub-toggles in Settings switch on and off.
    enum Target: Equatable, Sendable {
        case volume, brightness, keyboardLight
    }

    var target: Target {
        switch self {
        case .volumeUp, .volumeDown, .mute: .volume
        case .brightnessUp, .brightnessDown: .brightness
        case .keyboardLightUp, .keyboardLightDown, .keyboardLightToggle: .keyboardLight
        }
    }

    init?(code: Int) {
        switch Int32(truncatingIfNeeded: code) {
        case NX_KEYTYPE_SOUND_UP: self = .volumeUp
        case NX_KEYTYPE_SOUND_DOWN: self = .volumeDown
        case NX_KEYTYPE_MUTE: self = .mute
        case NX_KEYTYPE_BRIGHTNESS_UP: self = .brightnessUp
        case NX_KEYTYPE_BRIGHTNESS_DOWN: self = .brightnessDown
        case NX_KEYTYPE_ILLUMINATION_UP: self = .keyboardLightUp
        case NX_KEYTYPE_ILLUMINATION_DOWN: self = .keyboardLightDown
        case NX_KEYTYPE_ILLUMINATION_TOGGLE: self = .keyboardLightToggle
        default: return nil
        }
    }
}

/// One press or release of a `MediaKey`, read from a system-defined event.
nonisolated struct MediaKeyEvent: Equatable, Sendable {
    var key: MediaKey
    var isDown: Bool
    var isRepeat: Bool
    /// ⌥⇧ held: the step is a quarter of the usual one.
    var isFine: Bool

    /// nil for any other event, which then passes through untouched. `data1` holds the key code in its high 16 bits
    /// and the flags in its low 16: the key state in their high byte (0xA down, 0xB up) and the repeat flag in bit 0.
    init?(subtype: Int, data1: Int, modifiers: NSEvent.ModifierFlags) {
        guard subtype == Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS), let key = MediaKey(code: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        guard state == 0xA || state == 0xB else { return nil }
        self.init(key: key, isDown: state == 0xA, isRepeat: flags & 1 != 0, isFine: modifiers.isSuperset(of: [.option, .shift]))
    }

    init(key: MediaKey, isDown: Bool, isRepeat: Bool, isFine: Bool) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
        self.isFine = isFine
    }
}
