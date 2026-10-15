import AppKit

/// A key press as the watcher needs it: which key and whether shift or command was held. Never the character typed.
nonisolated struct KeyPress: Equatable, Sendable {
    var code: UInt16
    var shift = false
    var command = false

    /// Arrows, Home, End, Page Up, Page Down: with shift held they move the edge of a selection.
    private static let movingKeys: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121]
    private static let aKey: UInt16 = 0
    private static let cKey: UInt16 = 8

    /// Shift with a moving key extends a selection, and ⌘A selects everything.
    var changesSelection: Bool {
        (shift && Self.movingKeys.contains(code)) || (command && !shift && code == Self.aKey)
    }

    /// ⌘C: the most natural thing to do with a selection, and it leaves it as it is.
    var keepsSelection: Bool {
        command && !shift && code == Self.cKey
    }
}

/// What the watcher hears of the user's input in other apps, cut down at the source to what its rules need. Points are in
/// AppKit's screen coordinates.
nonisolated enum SelectionInput: Equatable, Sendable {
    case mouseDown(CGPoint)
    case mouseUp(CGPoint, clicks: Int)
    /// `pointer` is where the pointer was, the best guess at where a keyboard selection is when the app does not say.
    case keyUp(KeyPress, pointer: CGPoint)
    /// Another app came to the front.
    case applicationActivated(pid_t)
}

/// Where `SelectionInput` comes from; the system's monitors in the app, a fake in tests.
protocol SelectionInputSource: AnyObject {
    /// Starts delivering input to `handler`, replacing an earlier start. Key-ups only come with `keys`, which needs the
    /// Accessibility permission; the mouse and the front app need none.
    func start(_ handler: @escaping @MainActor (SelectionInput) -> Void, keys: Bool)
    func stop()
}

/// The system's global monitors. They see other apps' clicks and, with Accessibility, their key-ups, and never MyNotch's
/// own. Moves and drags are not listened to, so nothing runs while the pointer travels.
final class SystemSelectionInput: SelectionInputSource {
    private var monitor: Any?
    private var activation: (any NSObjectProtocol)?
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func start(_ handler: @escaping @MainActor (SelectionInput) -> Void, keys: Bool) {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: Self.mask(keys: keys)) { event in
            guard let input = SelectionInput(event) else { return }
            MainActor.assumeIsolated { handler(input) }
        }
        activation = workspace.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let processID = app.processIdentifier
            MainActor.assumeIsolated { handler(.applicationActivated(processID)) }
        }
    }

    /// Presses and releases of the left button, and key-ups only when asked: not moves, drags or key-downs, so nothing runs
    /// while the pointer travels or the user types.
    static func mask(keys: Bool) -> NSEvent.EventTypeMask {
        var mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp]
        if keys { mask.insert(.keyUp) }
        return mask
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let activation { workspace.notificationCenter.removeObserver(activation) }
        activation = nil
    }
}

extension SelectionInput {
    /// Reads from `event` only what each kind of event allows: a key event has no click count and a mouse event no key code,
    /// and asking raises.
    nonisolated init?(_ event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            self = .mouseDown(pointer)
        case .leftMouseUp:
            self = .mouseUp(pointer, clicks: event.clickCount)
        case .keyUp:
            let flags = event.modifierFlags
            self = .keyUp(KeyPress(code: event.keyCode, shift: flags.contains(.shift), command: flags.contains(.command)), pointer: pointer)
        default:
            return nil
        }
    }
}
