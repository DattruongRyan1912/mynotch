import AppKit

/// What the system hands the tap, reduced to what the HUD reads.
nonisolated enum EventTapInput: Sendable {
    /// A system-defined event: `data1` and `subtype` as `NSEvent` reports them.
    case systemDefined(subtype: Int, data1: Int, modifiers: NSEvent.ModifierFlags)
    /// macOS switched the tap off because it was slow or because of user input.
    case disabled
}

/// A `CGEventTap` over system-defined events, faked in tests so no real tap is ever created.
protocol EventTapping: AnyObject {
    /// Installs the tap at the head of the session's events; `handler` returns true to swallow the event, and must
    /// answer at once. False when macOS refuses, which it does without Accessibility. An installed tap is replaced.
    func install(_ handler: @escaping @MainActor (EventTapInput) -> Bool) -> Bool
    /// Switches an installed tap back on after macOS disabled it.
    func reenable()
    func uninstall()
    /// False when there is no tap, or macOS switched it off or invalidated it, which it does not always announce.
    var isAlive: Bool { get }
}

/// A level between 0 and 1 the media keys move: the built-in display's brightness or the keyboard light.
///
/// The controls below are used on the hardware queue and nowhere else, never from the tap callback.
nonisolated protocol LevelControlling: AnyObject {
    /// nil when there is nothing to control, e.g. a Mac without a built-in display or a backlit keyboard, or a private
    /// framework that lacks what is needed. The keys are then left to the system.
    func read() -> Float?
    /// False when it did not take.
    func write(_ level: Float) -> Bool
    /// Forgets which display or keyboard was found, which is looked up once and not on every press: the hardware may
    /// have changed.
    func refresh()
}

/// The default output device's volume, which can be set and muted.
nonisolated protocol VolumeControlling: AnyObject {
    /// nil when the default output device has no volume that can be set (many HDMI and aggregate devices).
    func read() -> VolumeState?
    /// False when the device has no mute.
    var canMute: Bool { get }
    func setLevel(_ level: Float) -> Bool
    func setMuted(_ muted: Bool) -> Bool
}

/// Where the hardware work behind a key runs: off the main thread, one piece after the other, so the tap callback
/// never waits for CoreAudio, DisplayServices or CoreBrightness. The result comes back on the main actor.
protocol HardwareQueue: AnyObject {
    func run<T: Sendable>(_ work: @escaping @Sendable () -> T, then completion: @escaping @MainActor (T) -> Void)
}

/// Tells when the default output device, the displays or the keyboard may have changed, so what the keys can do is
/// looked at again then and not at every press.
protocol HardwareChangeSource: AnyObject {
    /// Calls `onChange` on every change until `stop()`. Starting again replaces the earlier call.
    func start(_ onChange: @escaping @MainActor () -> Void)
    func stop()
}
