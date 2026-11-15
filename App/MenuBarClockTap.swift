import AppKit
import MyNotchCore

/// Holds back a click on the clock while the system hides apps, for `MenuBarClockPassage` to open Notification Center: an
/// event tap that can swallow the click (Accessibility, which hiding needs anyway), on only while something is hidden. The
/// clock is the rightmost of the system's own items on a display's menu bar; where they are is read through Accessibility
/// when the tap is switched on and when the displays change, never inside the tap, which the system turns off when slow.
final class MenuBarClockTap {
    /// Marks the replayed click, which the tap lets through.
    private static let replayMark: Int64 = 0x4D79_4E63
    private static let menuBarAgent = "com.apple.MenuBarAgent"
    private static let notificationCenter = "com.apple.notificationcenterui"

    private let passage: MenuBarClockPassage
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var clocks: [CGRect] = []
    /// The mouse-up of a held click is swallowed too.
    private var swallowsUp = false
    /// Where the held click came down, where the replay clicks.
    private var clickedAt = CGPoint.zero
    /// Unlocking and waking: a locked screen's menu bar has no items to read, so the clocks are read again.
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(scheduler: any Scheduler, suspend: @escaping () -> Bool, resume: @escaping () -> Void) {
        var replay: () -> Void = {}
        passage = MenuBarClockPassage(
            scheduler: scheduler, isPanelOpen: Self.isNotificationCenterOpen, suspend: suspend, resume: resume, replay: { replay() }
        )
        replay = { [weak self] in self.map { Self.click(at: $0.clickedAt) } }
        passage.onStep = { step in Log.logger(category: "app").notice("Menu-bar hider: \(step, privacy: .public)") }
        let again: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.displaysChanged() } }
        let unlocked = DistributedNotificationCenter.default()
        observers.append((unlocked, unlocked.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: again)))
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: again)))
    }

    isolated deinit {
        observers.forEach { $0.center.removeObserver($0.token) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    /// On while the system hides apps.
    func setRunning(_ running: Bool) {
        if running {
            findClocks()
            start()
        } else {
            passage.cancel()
            swallowsUp = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        }
    }

    func displaysChanged() {
        guard let tap, CGEvent.tapIsEnabled(tap: tap) else { return }
        findClocks()
    }

    private func start() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return
        }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue | 1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MenuBarClockTap>.fromOpaque(info).takeUnretainedValue()
                let location = event.location
                let isReplay = event.getIntegerValueField(.eventSourceUserData) == MenuBarClockTap.replayMark
                let swallows = MainActor.assumeIsolated { tap.swallows(type, at: location, isReplay: isReplay) }
                return swallows ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.logger(category: "app").error("Menu-bar hider: no event tap for the clock, Notification Center stays blocked while icons are hidden")
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// Whether the event goes no further.
    private func swallows(_ type: CGEventType, at location: CGPoint, isReplay: Bool) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case _ where isReplay:
            return false
        case .leftMouseUp where swallowsUp:
            swallowsUp = false
            return true
        case .leftMouseDown:
            guard clocks.contains(where: { $0.contains(location) }), passage.clockPressed() else { return false }
            clickedAt = location
            swallowsUp = true
            return true
        default:
            return false
        }
    }

    /// The rightmost of the system's items on each display's menu bar, in the events' coordinates (top-left origin).
    private func findClocks() {
        clocks = Self.readClocks()
        Log.logger(category: "app").notice("Menu-bar hider: found the clock on \(self.clocks.count) displays")
    }

    private static func readClocks() -> [CGRect] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: menuBarAgent).first else {
            return []
        }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var bar: CFTypeRef?
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &bar) == .success,
              let bar, AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else {
            return []
        }
        let frames = items.compactMap(frame(of:))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.compactMap { screen in
            // The display's top strip, taller than any menu bar.
            let strip = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: 60)
            return frames.filter { strip.contains(CGPoint(x: $0.midX, y: $0.midY)) }.max { $0.maxX < $1.maxX }
        }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return extent.width > 0 ? CGRect(origin: origin, size: extent) : nil
    }

    /// Notification Center's panel covers a whole display; its banners are smaller windows of the same app.
    private static func isNotificationCenterOpen() -> Bool {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: notificationCenter).first?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let sizes = Set(NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" })
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return sizes.contains("\(Int(frame.width))x\(Int(frame.height))")
        }
    }

    private static func click(at point: CGPoint) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
            event.setIntegerValueField(.eventSourceUserData, value: replayMark)
            event.post(tap: .cghidEventTap)
            // A press as short as a person's, as when it was tried.
            if type == .leftMouseDown { usleep(50_000) }
        }
    }
}
