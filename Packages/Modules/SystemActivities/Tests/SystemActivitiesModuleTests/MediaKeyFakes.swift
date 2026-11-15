import AppKit
@testable import SystemActivitiesModule

/// Stands in for the `CGEventTap`: tests press keys through the installed handler, nothing reaches the system.
final class FakeEventTap: EventTapping {
    private var handler: (@MainActor (EventTapInput) -> Bool)?
    var isInstalled: Bool { handler != nil }
    /// Whether macOS would let the tap in.
    var canInstall = true
    /// macOS switched the installed tap off without a `tapDisabled…` event, or invalidated it.
    var killed = false
    /// Whether switching a killed tap back on works.
    var revivable = true
    private(set) var installCount = 0
    private(set) var reenableCount = 0
    private(set) var uninstallCount = 0

    var isAlive: Bool { handler != nil && !killed }

    func install(_ handler: @escaping @MainActor (EventTapInput) -> Bool) -> Bool {
        installCount += 1
        guard canInstall else { return false }
        self.handler = handler
        killed = false
        return true
    }

    func reenable() {
        reenableCount += 1
        if revivable { killed = false }
    }

    func uninstall() {
        uninstallCount += 1
        handler = nil
    }

    /// The event as macOS delivers it: `data1` carries the key code and the state. True when the HUD swallowed it.
    @discardableResult
    func press(
        _ key: MediaKey, down: Bool = true, isRepeat: Bool = false, fine: Bool = false, modifiers: NSEvent.ModifierFlags = []
    ) -> Bool {
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
        return send(.systemDefined(subtype: 8, data1: data1, modifiers: fine ? modifiers.union([.option, .shift]) : modifiers))
    }

    @discardableResult
    func send(_ input: EventTapInput) -> Bool { handler?(input) ?? false }
}

/// Runs the hardware work only when a test says so, on the test's own thread, so a test can see what the tap callback
/// did before any of it ran.
nonisolated final class FakeHardwareQueue: HardwareQueue, @unchecked Sendable {
    private var pending: [() -> Void] = []

    var pendingCount: Int { pending.count }

    func run<T: Sendable>(_ work: @escaping @Sendable () -> T, then completion: @escaping @MainActor (T) -> Void) {
        pending.append {
            let result = work()
            MainActor.assumeIsolated { completion(result) }
        }
    }

    /// Runs everything queued, and what that queues in turn, in order.
    func drain() {
        while !pending.isEmpty { pending.removeFirst()() }
    }
}

final class FakeHardwareChanges: HardwareChangeSource {
    private var onChange: (@MainActor () -> Void)?
    var isListening: Bool { onChange != nil }
    private(set) var startCount = 0

    func start(_ onChange: @escaping @MainActor () -> Void) {
        startCount += 1
        self.onChange = onChange
    }

    func stop() { onChange = nil }

    /// The default output device, a display or the keyboard changed.
    func fire() { onChange?() }
}

nonisolated final class FakeVolumeControl: VolumeControlling {
    var state: VolumeState? = VolumeState(level: 0.5, muted: false)
    var canMute = true
    private(set) var readCount = 0
    private(set) var writeCount = 0

    func read() -> VolumeState? {
        readCount += 1
        return state
    }

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

nonisolated final class FakeLevelControl: LevelControlling {
    var level: Float?
    /// A control that reads fine but does not take what is written.
    var refusesWrites = false
    private(set) var readCount = 0
    private(set) var refreshCount = 0
    private(set) var writes: [Float] = []

    init(level: Float? = 0.5) { self.level = level }

    func read() -> Float? {
        readCount += 1
        return level
    }

    func refresh() { refreshCount += 1 }

    func write(_ level: Float) -> Bool {
        guard self.level != nil, !refusesWrites else { return false }
        writes.append(level)
        self.level = level
        return true
    }
}
