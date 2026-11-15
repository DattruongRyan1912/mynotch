import AppKit
import SwiftUI

public enum TitlebarDoubleClickAction: Equatable {
    case zoom
    case minimize
    case none

    public static func resolve(preference: String?) -> TitlebarDoubleClickAction {
        guard let preference, !preference.isEmpty else {
            return .zoom
        }
        switch preference {
        case "Minimize":
            return .minimize
        case "None":
            return .none
        case "Maximize":
            return .zoom
        default:
            return .zoom
        }
    }
}

@MainActor
public protocol TitlebarWindowActing: AnyObject {
    func performZoom(_ sender: Any?)
    func performMiniaturize(_ sender: Any?)
    func performDrag(with event: NSEvent)
}

extension NSWindow: TitlebarWindowActing {}

public final class TitlebarInteractionView: NSView {
    public var preferenceProvider: () -> String? = {
        UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
    }
    public var actorOverride: (any TitlebarWindowActing)?

    private var pendingMouseDownEvent: NSEvent?
    private var hasPerformedDrag: Bool = false

    override public var mouseDownCanMoveWindow: Bool { false }
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override public func mouseDown(with event: NSEvent) {
        let actor = actorOverride ?? (window as (any TitlebarWindowActing)?)
        guard let actor else { return }

        if event.clickCount == 2 {
            pendingMouseDownEvent = nil
            hasPerformedDrag = false
            let action = TitlebarDoubleClickAction.resolve(preference: preferenceProvider())
            switch action {
            case .zoom:
                actor.performZoom(nil)
            case .minimize:
                actor.performMiniaturize(nil)
            case .none:
                break
            }
        } else if event.clickCount == 1 {
            pendingMouseDownEvent = event
            hasPerformedDrag = false
        } else {
            pendingMouseDownEvent = nil
            hasPerformedDrag = false
        }
    }

    override public func mouseDragged(with event: NSEvent) {
        guard !hasPerformedDrag, let initial = pendingMouseDownEvent else { return }
        let actor = actorOverride ?? (window as (any TitlebarWindowActing)?)
        guard let actor else { return }

        let dx = event.locationInWindow.x - initial.locationInWindow.x
        let dy = event.locationInWindow.y - initial.locationInWindow.y
        if hypot(dx, dy) >= 3.0 {
            hasPerformedDrag = true
            actor.performDrag(with: initial)
        }
    }

    override public func mouseUp(with event: NSEvent) {
        pendingMouseDownEvent = nil
        hasPerformedDrag = false
    }
}

public struct TitlebarDoubleClickArea: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> TitlebarInteractionView {
        TitlebarInteractionView()
    }

    public func updateNSView(_ nsView: TitlebarInteractionView, context: Context) {}
}
