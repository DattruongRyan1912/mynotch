import AppKit

/// The real events: the pointer is read 60 times a second, and a global monitor reports the mouse buttons and, with Accessibility,
/// the moment a key goes down. A monitor sees the other apps' events, not MyNotch's own, which is right: MyNotch's windows are not
/// in the video. A key is reported as a moment; which key it was is never read.
final class SystemActivityEvents: ActivityEventSource {
    private var timer: Timer?
    private var monitors: [Any] = []

    func start(sink: any ActivityEventSink, includesKeys: Bool) {
        stop()
        sink.pointerMoved(toAppKit: NSEvent.mouseLocation)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { sink.pointerMoved(toAppKit: NSEvent.mouseLocation) }
        }
        // Common modes, so it keeps going while a menu is open or a control is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in
            let button: ClickButton = event.type == .rightMouseDown ? .right : .left
            MainActor.assumeIsolated { sink.click(button, atAppKit: NSEvent.mouseLocation) }
        }) {
            monitors.append(clicks)
        }
        if includesKeys, let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ in sink.keyPressed() }) {
            monitors.append(keys)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
