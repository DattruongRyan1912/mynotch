import AppKit
import ObjectiveC

/// Draws a window's Liquid Glass as an active window draws it, without making the window key. The notch's panel always has it while
/// the look is Liquid Glass (`NotchGlassSupport` can turn it off).
///
/// macOS draws the glass of a window that is not key in a subdued style: a heavy blur, no edge lensing, no rim, no shadow. SwiftUI
/// reads the window's *key appearance* for it and changes the parameters of the glass's backdrop filter (probed in a window, with the
/// layer tree of a hosted `glassEffect`: a window made key, and the same window only given the key appearance, have the same filter
/// parameters; one without them has the subdued ones). The notch's panel is never key while the pointer is only over it, and must
/// not be: R2a's pinned paste needs "no MyNotch window is key", the keyboard goes back to the app in front, and typing would go to
/// the notch.
///
/// The key appearance is a different piece of state from key status. `NSWindow.acquireKeyAppearance` is what AppKit's window theme
/// calls when a window becomes key (it sets the window's appearance flags, tells the first responder, and tells the window server);
/// `isKeyWindow` reads another flag, so calling it on its own changes none of `isKeyWindow`, `NSApp.keyWindow` and `canBecomeKey`
/// (tests pin that). `resignKeyAppearance` is its undo.
///
/// There is no public way: SwiftUI's `appearsActive` environment value changes nothing in the glass (the same probe), and
/// `NSVisualEffectView.state` and `NSGlassEffectView` have no counterpart for SwiftUI's glass. Both methods are private, so each
/// call is guarded: the instance method has to exist on the window's class and have the encoding of `void method(void)`; with
/// anything else the hook does nothing.
///
/// AppKit takes the appearance back whenever the window resigns key, and may on other changes (the app activating or deactivating,
/// the window changing screen or occlusion), so `NotchPanel` gives it back after each.
struct ActiveGlassAppearance: Equatable {
    /// The selector names, kept as text so that a test can name one the window does not have.
    var acquireName = "acquireKeyAppearance"
    var resignName = "resignKeyAppearance"

    /// The appearance, if the running macOS has both methods in the form this expects; nil if not, which is what the switch then does.
    static func detect() -> ActiveGlassAppearance? {
        let appearance = ActiveGlassAppearance()
        return appearance.isAvailable(on: NSWindow.self) ? appearance : nil
    }

    /// Whether windows of `windowClass` have both methods as `void method(void)`.
    func isAvailable(on windowClass: AnyClass) -> Bool {
        implementation(of: acquireName, on: windowClass) != nil && implementation(of: resignName, on: windowClass) != nil
    }

    /// Whether `window` has the key appearance, as AppKit's window theme says; nil if this macOS has no such method. For the log: it
    /// tells a notch that is soft because the flag was dropped from one that is soft for another reason.
    static func hasAppearance(_ window: NSWindow) -> Bool? {
        guard window.responds(to: NSSelectorFromString("hasKeyAppearance")) else { return nil }
        return window.value(forKey: "hasKeyAppearance") as? Bool
    }

    /// Gives `window` the key appearance. False, and nothing done, if the method is missing.
    @discardableResult
    func acquire(on window: NSWindow) -> Bool {
        call(acquireName, on: window)
    }

    /// Takes the key appearance back from `window`, unless it is key, which has the appearance by right. False, and nothing done, if
    /// the method is missing or the window is key.
    @discardableResult
    func release(on window: NSWindow) -> Bool {
        guard !window.isKeyWindow else { return false }
        return call(resignName, on: window)
    }

    private typealias Method = @convention(c) (AnyObject, Selector) -> Void

    private func implementation(of name: String, on windowClass: AnyClass) -> Method? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(windowClass, selector), let encoding = method_getTypeEncoding(method),
              String(cString: encoding).hasPrefix("v16@0:8") else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: Method.self)
    }

    private func call(_ name: String, on window: NSWindow) -> Bool {
        guard let implementation = implementation(of: name, on: type(of: window)) else { return false }
        implementation(window, NSSelectorFromString(name))
        return true
    }
}
