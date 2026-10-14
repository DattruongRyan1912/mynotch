import AppKit
@testable import SystemActivitiesModule

/// Stands in for the `CGEventTap`: tests press keys through the installed handler, nothing reaches the system.
final class FakeEventTap: EventTapping {
    private var handler: (@MainActor (EventTapInput) -> Bool)?
    var isInstalled: Bool { handler != nil }
    /// Whether macOS would let the tap in.
    var canInstall = true
    private(set) var installCount = 0
    private(set) var reenableCount = 0
    private(set) var uninstallCount = 0

    func install(_ handler: @escaping @MainActor (EventTapInput) -> Bool) -> Bool {
        installCount += 1
        guard canInstall else { return false }
        self.handler = handler
        return true
    }

    func reenable() { reenableCount += 1 }

    func uninstall() {
        uninstallCount += 1
        handler = nil
    }

    /// The event as macOS delivers it: `data1` carries the key code and the state. True when the HUD swallowed it.
    @discardableResult
    func press(_ key: MediaKey, down: Bool = true, isRepeat: Bool = false, fine: Bool = false) -> Bool {
        let code = switch key {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .brightnessUp: 2
        case .brightnessDown: 3
        case .keyboardLightUp: 21
        case .keyboardLightDown: 22
        case .keyboardLightToggle: 23
        }
        let data1 = (code << 16) | ((down ? 0xA : 0xB) << 8) | (isRepeat ? 1 : 0)
        return send(.systemDefined(subtype: 8, data1: data1, modifiers: fine ? [.option, .shift] : []))
    }

    @discardableResult
    func send(_ input: EventTapInput) -> Bool { handler?(input) ?? false }
}

final class FakeVolumeControl: VolumeControlling {
    var state: VolumeState? = VolumeState(level: 0.5, muted: false)
    var canMute = true
    private(set) var writeCount = 0

    func read() -> VolumeState? { state }

    func setLevel(_ level: Float) -> Bool {
        guard state != nil else { return false }
        writeCount += 1
        state?.level = level
        return true
    }

    func setMuted(_ muted: Bool) -> Bool {
        guard state != nil, canMute else { return false }
        writeCount += 1
        state?.muted = muted
        return true
    }
}

final class FakeLevelControl: LevelControlling {
    var level: Float?
    private(set) var writes: [Float] = []

    init(level: Float? = 0.5) { self.level = level }

    func read() -> Float? { level }

    func write(_ level: Float) -> Bool {
        guard self.level != nil else { return false }
        writes.append(level)
        self.level = level
        return true
    }
}
