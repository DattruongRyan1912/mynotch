import AppKit

/// `EventTapping` over a real `CGEventTap` on the main run loop, so the callback runs on the main thread.
final class SystemEventTap: EventTapping {
    /// `NX_SYSDEFINED`: where the media keys arrive.
    private nonisolated static let systemDefined: UInt32 = 14

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: (@MainActor (EventTapInput) -> Bool)?

    init() {}

    isolated deinit { uninstall() }

    func install(_ handler: @escaping @MainActor (EventTapInput) -> Bool) -> Bool {
        uninstall()
        // `defaultTap` can change or swallow events, which needs Accessibility; without it, creating the tap returns nil.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << Self.systemDefined, callback: systemEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        self.handler = handler
        return true
    }

    func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func uninstall() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        handler = nil
    }

    /// What the HUD reads of an event; nil for any other, which passes through.
    fileprivate nonisolated static func input(for type: CGEventType, _ event: CGEvent) -> EventTapInput? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return .disabled
        default:
            guard type.rawValue == systemDefined, let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined else { return nil }
            return .systemDefined(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1, modifiers: nsEvent.modifierFlags)
        }
    }

    /// Whether the event is swallowed. The handler is held for the call, so it may uninstall the tap.
    fileprivate func receive(_ input: EventTapInput) -> Bool {
        guard let handler else { return false }
        return handler(input)
    }
}

/// The tap sits on the main run loop, so this always runs on the main thread. Returning nil swallows the event.
private nonisolated func systemEventTapCallback(
    _ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo, let input = SystemEventTap.input(for: type, event) else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<SystemEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    let swallowed = MainActor.assumeIsolated { tap.receive(input) }
    return swallowed ? nil : Unmanaged.passUnretained(event)
}
