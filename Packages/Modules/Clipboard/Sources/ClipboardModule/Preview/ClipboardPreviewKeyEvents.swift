import AppKit

/// What a window tells the preview's key table about the event it is looking at, and about what has the keyboard.
extension ClipboardPreviewKeys {
    /// What a window does with a key press: asks `handler` (the window's model) what the preview makes of it, with where typing would
    /// go and whether an input method is composing. True when the preview took it, so the field or view never sees it.
    typealias Handler = (Key, Target, Bool) -> Bool

    @MainActor
    static func offer(_ event: NSEvent, in window: NSWindow, to handler: Handler?, isCards: (NSResponder?) -> Bool) -> Bool {
        guard let handler, let target = Target(responder: window.firstResponder, isCards: isCards) else { return false }
        return handler(Key(event), target, hasMarkedText(window.firstResponder))
    }

    /// An input method is composing in this text (Telex, VNI, an accent about to be completed): Space, Return and Esc are its.
    @MainActor
    static func hasMarkedText(_ responder: NSResponder?) -> Bool {
        (responder as? any NSTextInputClient)?.hasMarkedText() ?? false
    }
}

extension ClipboardPreviewKeys.Key {
    @MainActor
    init(_ event: NSEvent) {
        self.init(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags, isRepeat: event.isARepeat
        )
    }
}

extension ClipboardPreviewKeys.Target {
    /// Where typing would go, for what has the keyboard. The editor of a search field is where text goes. Another text field's
    /// editor (a password, a name being typed) is nil: the preview never takes a key there. Anything else is `.cards` when
    /// `isCards` says so (the library's cards; in the panel anything), and nil otherwise (a sidebar, a button).
    @MainActor
    init?(responder: NSResponder?, isCards: (NSResponder?) -> Bool) {
        if let text = responder as? NSText {
            guard text.delegate is NSSearchField else { return nil }
            self = .searchField
        } else if isCards(responder) {
            self = .cards
        } else {
            return nil
        }
    }
}
