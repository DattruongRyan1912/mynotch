import AppKit
import CoreGraphics
import Foundation
import Synchronization

/// The real events: the pointer is read 60 times a second, and a CGEventTap together with global and local AppKit monitors
/// report mouse buttons and key presses.
/// Events are captured across external applications and MyNotch's own windows.
final class SystemActivityEvents: ActivityEventSource {
    private struct ClickState {
        var lastTime: TimeInterval = 0
        var lastPoint: CGPoint = .zero
        var lastButton: ClickButton? = nil
    }

    private var timer: Timer?
    private var monitors: [Any] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private weak var currentSink: (any ActivityEventSink)?
    private var recordsKeys = false

    private let clickState = Mutex(ClickState())
    private let lastKeyTime = Mutex<TimeInterval>(0)

    func start(sink: any ActivityEventSink, includesKeys: Bool) {
        stop()
        currentSink = sink
        recordsKeys = includesKeys
        sink.pointerMoved(toAppKit: NSEvent.mouseLocation)

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            sink.pointerMoved(toAppKit: NSEvent.mouseLocation)
        }
        // Common modes, so it keeps going while a menu is open or a control is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        installEventTap(sink: sink, includesKeys: includesKeys)
        installAppKitMonitors(sink: sink, includesKeys: includesKeys)
    }

    private func installEventTap(sink: any ActivityEventSink, includesKeys: Bool) {
        var mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)
        if includesKeys {
            mask |= (1 << CGEventType.keyDown.rawValue)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let source = Unmanaged<SystemActivityEvents>.fromOpaque(refcon).takeUnretainedValue()
                source.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )

        if let tap {
            eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        switch type {
        case .leftMouseDown, .otherMouseDown:
            recordClick(.left, at: NSEvent.mouseLocation)
        case .rightMouseDown:
            recordClick(.right, at: NSEvent.mouseLocation)
        case .keyDown:
            recordKey()
        default:
            break
        }
    }

    private func recordClick(_ button: ClickButton, at point: CGPoint) {
        guard let sink = currentSink else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let shouldRecord = clickState.withLock { state -> Bool in
            let dt = now - state.lastTime
            let dx = point.x - state.lastPoint.x
            let dy = point.y - state.lastPoint.y
            let distSq = dx * dx + dy * dy
            // Deduplicate: same button within 50ms and 5 points radius
            if dt < 0.05 && state.lastButton == button && distSq < 25.0 {
                return false
            }
            state.lastTime = now
            state.lastPoint = point
            state.lastButton = button
            return true
        }
        if shouldRecord {
            sink.click(button, atAppKit: point)
        }
    }

    private func recordKey() {
        guard recordsKeys, let sink = currentSink else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let shouldRecord = lastKeyTime.withLock { last -> Bool in
            let dt = now - last
            // Deduplicate: duplicate key event from tap + monitor within 40ms
            if dt < 0.04 {
                return false
            }
            last = now
            return true
        }
        if shouldRecord {
            sink.keyPressed()
        }
    }

    private func installAppKitMonitors(sink: any ActivityEventSink, includesKeys: Bool) {
        // Global monitors (events in other applications)
        if let globalClicks = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] event in
                let button: ClickButton = event.type == .rightMouseDown ? .right : .left
                self?.recordClick(button, at: NSEvent.mouseLocation)
            }
        ) {
            monitors.append(globalClicks)
        }

        if includesKeys, let globalKeys = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] _ in
                self?.recordKey()
            }
        ) {
            monitors.append(globalKeys)
        }

        // Local monitors (events in MyNotch's own windows / menus)
        if let localClicks = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] event in
                let button: ClickButton = event.type == .rightMouseDown ? .right : .left
                self?.recordClick(button, at: NSEvent.mouseLocation)
                return event
            }
        ) {
            monitors.append(localClicks)
        }

        if includesKeys, let localKeys = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                self?.recordKey()
                return event
            }
        ) {
            monitors.append(localKeys)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        clickState.withLock {
            $0.lastTime = 0
            $0.lastPoint = .zero
            $0.lastButton = nil
        }
        lastKeyTime.withLock { $0 = 0 }
        currentSink = nil
    }
}

