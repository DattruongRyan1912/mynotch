import Foundation

/// The keyboard backlight through `KeyboardBrightnessClient`, a class of the private CoreBrightness framework that is
/// looked up at runtime so nothing links against it. A missing class or method, or a Mac without a backlit keyboard,
/// makes it unavailable: `read` is nil and the keyboard light keys stay the system's.
final class CoreBrightnessKeyboardLight: LevelControlling {
    static let libraryPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

    private static let keyboardIDs = Selector(("copyKeyboardBacklightIDs"))
    private static let getBrightness = Selector(("brightnessForKeyboard:"))
    private static let setBrightness = Selector(("setBrightness:forKeyboard:"))

    private typealias Getter = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Setter = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private struct Client {
        let object: NSObject
        let get: Getter
        let set: Setter

        /// nil when the object lacks any of the three methods.
        init?(_ object: NSObject?) {
            guard let object,
                  object.responds(to: CoreBrightnessKeyboardLight.keyboardIDs),
                  object.responds(to: CoreBrightnessKeyboardLight.getBrightness),
                  object.responds(to: CoreBrightnessKeyboardLight.setBrightness) else { return nil }
            self.object = object
            get = unsafeBitCast(object.method(for: CoreBrightnessKeyboardLight.getBrightness), to: Getter.self)
            set = unsafeBitCast(object.method(for: CoreBrightnessKeyboardLight.setBrightness), to: Setter.self)
        }

        /// The first keyboard with a backlight.
        var keyboardID: UInt64? {
            // `copy…` hands the array over owned.
            let ids = object.perform(CoreBrightnessKeyboardLight.keyboardIDs)?.takeRetainedValue() as? [NSNumber]
            return ids?.first?.uint64Value
        }
    }

    /// Made on first use, so creating this loads nothing.
    private lazy var client = Client(makeClient())
    private let makeClient: () -> NSObject?

    /// The framework is never unloaded.
    convenience init() {
        self.init(makeClient: {
            _ = dlopen(Self.libraryPath, RTLD_LAZY | RTLD_LOCAL)
            return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
        })
    }

    /// `makeClient` is first called at the first `read` or `write`, and none of the client's methods before then.
    init(makeClient: @escaping () -> NSObject?) {
        self.makeClient = makeClient
    }

    func read() -> Float? {
        guard let client, let id = client.keyboardID else { return nil }
        let level = client.get(client.object, Self.getBrightness, id)
        return (0...1).contains(level) ? level : nil
    }

    func write(_ level: Float) -> Bool {
        guard let client, let id = client.keyboardID else { return false }
        return client.set(client.object, Self.setBrightness, min(max(level, 0), 1), id)
    }
}
