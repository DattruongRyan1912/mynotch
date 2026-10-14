import AppKit

/// Gives the keyboard from a window of MyNotch that stays on screen back to the app in front: the notch's panel when
/// its tab stops wanting typing, and any other panel of MyNotch before it sends the app behind a key press (the
/// clipboard's floating panel before ⌘V). One implementation, so whatever a real machine teaches about it, through
/// `KeyboardReturn`, reaches every window that uses it. Key status only returns when a key window leaves the screen, so
/// the default hands it to a hidden 1 pt panel and orders that one out, and the visible window is never touched.
public final class KeyboardHandBack {
    private var sink: KeySinkPanel?
    private let strategy: () -> KeyboardReturn
    private let performStep: ((KeyboardReturn.Step, NSWindow, NSRunningApplication?) -> Void)?
    private let check: (NSRunningApplication?) -> Bool

    public convenience init() {
        self.init(strategy: { .current }, perform: nil, check: { KeyboardHandBack.keyboardIsWith($0) })
    }

    /// Tests replace the AppKit steps and the check, so no window is shown and no key status moves.
    init(
        strategy: @escaping () -> KeyboardReturn,
        perform: ((KeyboardReturn.Step, NSWindow, NSRunningApplication?) -> Void)?,
        check: @escaping (NSRunningApplication?) -> Bool
    ) {
        self.strategy = strategy
        performStep = perform
        self.check = check
    }

    /// Takes key status from `window` and gives it to `front`, the app that was in front (by default the one that is now).
    /// True when that worked as far as AppKit can tell: afterwards no window of MyNotch is key and `front` is still in
    /// front. False means a key press would reach MyNotch, or nobody, so the caller must not send one.
    @discardableResult
    public func returnKeyboard(from window: NSWindow, to front: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) -> Bool {
        returnKeyboard(
            from: window, to: front, frontIsOtherApp: Self.isOtherApp(pid: front?.processIdentifier, own: ProcessInfo.processInfo.processIdentifier)
        )
    }

    func returnKeyboard(from window: NSWindow, to front: NSRunningApplication?, frontIsOtherApp: Bool) -> Bool {
        let strategy = strategy()
        let steps = strategy.steps(frontIsOtherApp: frontIsOtherApp)
        NotchLog.record("keyboard hand-back strategy=\(strategy.rawValue) steps=\(steps.map(\.rawValue)) frontIsOtherApp=\(frontIsOtherApp) \(window.logSummary)")
        for step in steps {
            if let performStep {
                performStep(step, window, front)
            } else {
                perform(step, window: window, front: front)
            }
        }
        let isBack = check(front)
        NotchLog.record("keyboard hand-back done back=\(isBack) \(window.logSummary)")
        return isBack
    }

    /// Drops the hidden panel; the next hand-back makes a new one. Call it when the window that hands back goes.
    public func close() {
        sink?.orderOut(nil)
        sink?.close()
        sink = nil
    }

    /// Whether a key press now reaches `front`, the app that was in front: the keyboard has no window of MyNotch to go
    /// to, and `front` is still in front. The check for a window that has already left the screen.
    public static func keyboardIsWith(_ front: NSRunningApplication?) -> Bool {
        keyboardIsWith(
            expected: front?.processIdentifier, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            own: ProcessInfo.processInfo.processIdentifier, hasKeyWindow: NSApplication.shared.windows.contains(where: \.isKeyWindow)
        )
    }

    /// `expected` is the app the keyboard was meant for; nil accepts any other app in front. MyNotch in front is never
    /// good: its own window would get the key.
    static func keyboardIsWith(expected: pid_t?, frontmost: pid_t?, own: pid_t, hasKeyWindow: Bool) -> Bool {
        guard !hasKeyWindow, let frontmost, frontmost != own else { return false }
        return expected == nil || expected == frontmost
    }

    /// An app other than MyNotch is in front, so there is someone to give the keyboard to.
    static func isOtherApp(pid: pid_t?, own: pid_t) -> Bool {
        pid.map { $0 != own } ?? false
    }

    private func perform(_ step: KeyboardReturn.Step, window: NSWindow, front: NSRunningApplication?) {
        switch step {
        case .showSink:
            let sink = sink ?? KeySinkPanel()
            self.sink = sink
            // Inside the window at its top edge, where nothing can be seen of a clear 1 pt window.
            sink.setFrame(CGRect(x: window.frame.midX - 0.5, y: window.frame.maxY - 1, width: 1, height: 1), display: false)
            sink.orderFrontRegardless()
        case .makeSinkKey: sink?.makeKey()
        case .hideSink: sink?.orderOut(nil)
        case .activateFrontApp: _ = front?.activate()
        case .orderNotchOut: window.orderOut(nil)
        case .orderNotchIn: window.orderFrontRegardless()
        }
    }
}
