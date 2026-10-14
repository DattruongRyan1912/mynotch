import Foundation

/// How the notch panel gives the keyboard back to the app in front. Key status only returns when a key window leaves
/// the screen, and doing that to the notch panel makes the whole notch blink, so the default hands key status to a
/// hidden 1 pt panel and orders that one out instead; the visible notch is never touched.
enum KeyboardReturn: String, CaseIterable {
    /// Hidden panel takes key status and leaves.
    case sinkPanel
    /// The same, then asks the app that was in front to become active again, as a belt for the case that leaving did not return the keyboard.
    case sinkAndActivate
    /// Orders the notch panel itself out and in: the original mechanism, which blinks. Kept to compare on a real machine.
    case orderOutIn

    /// One AppKit call each, in order; the controller only executes them.
    enum Step: String, Equatable {
        case showSink, makeSinkKey, hideSink
        case activateFrontApp
        case orderNotchOut, orderNotchIn
    }

    /// `frontIsOtherApp`: an app other than MyNotch is frontmost, so there is someone to give the keyboard to.
    func steps(frontIsOtherApp: Bool) -> [Step] {
        let sink: [Step] = [.showSink, .makeSinkKey, .hideSink]
        return switch self {
        case .sinkPanel: sink
        case .sinkAndActivate: frontIsOtherApp ? sink + [.activateFrontApp] : sink
        case .orderOutIn: [.orderNotchOut, .orderNotchIn]
        }
    }

    /// Unknown or missing values mean the default.
    init(defaultsValue: String?) {
        self = defaultsValue.flatMap(Self.init(rawValue:)) ?? .sinkPanel
    }

    /// Debug builds read the user default `MyNotchKeyboardReturn` (`defaults write <bundle id> MyNotchKeyboardReturn -string orderOutIn`), so
    /// the mechanisms can be compared on a real machine without a rebuild; release builds always use the default.
    static var current: KeyboardReturn {
        #if DEBUG
        KeyboardReturn(defaultsValue: UserDefaults.standard.string(forKey: "MyNotchKeyboardReturn"))
        #else
        .sinkPanel
        #endif
    }
}
