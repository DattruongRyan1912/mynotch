import CoreGraphics
import Foundation

/// The built-in display's brightness through the private DisplayServices framework, loaded with `dlopen` and `dlsym`
/// so nothing links against it. A missing function, or no built-in display, makes it unavailable: `read` is nil and
/// the brightness keys stay the system's. The display is looked up once, and again after `refresh()`.
nonisolated final class DisplayServicesBrightness: LevelControlling {
    static let libraryPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private struct Functions {
        let get: @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let set: @convention(c) (CGDirectDisplayID, Float) -> Int32
        /// Optional: older systems lack it, and the display is then assumed to be controllable.
        let canChange: (@convention(c) (CGDirectDisplayID) -> Bool)?

        /// nil when `get` or `set` is missing.
        init?(resolve: (String) -> UnsafeMutableRawPointer?) {
            guard let get = resolve("DisplayServicesGetBrightness"), let set = resolve("DisplayServicesSetBrightness") else { return nil }
            self.get = unsafeBitCast(get, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
            self.set = unsafeBitCast(set, to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)
            canChange = resolve("DisplayServicesCanChangeBrightness")
                .map { unsafeBitCast($0, to: (@convention(c) (CGDirectDisplayID) -> Bool).self) }
        }
    }

    private struct Lookup {
        let display: CGDirectDisplayID?
    }

    private var lookup: Lookup?
    /// Resolved on first use, so creating this loads nothing.
    private lazy var functions = Functions(resolve: resolve)
    private let resolve: (String) -> UnsafeMutableRawPointer?
    private let builtInDisplay: () -> CGDirectDisplayID?

    /// Loading the library again is cheap and it is never unloaded, which the resolved functions rely on.
    convenience init() {
        self.init(
            resolve: { name in dlopen(Self.libraryPath, RTLD_LAZY | RTLD_LOCAL).flatMap { dlsym($0, name) } },
            builtInDisplay: Self.activeBuiltInDisplay)
    }

    /// `resolve` is first called at the first `read` or `write`; nothing it returns is called before then.
    init(resolve: @escaping (String) -> UnsafeMutableRawPointer?, builtInDisplay: @escaping () -> CGDirectDisplayID?) {
        self.resolve = resolve
        self.builtInDisplay = builtInDisplay
    }

    func refresh() { lookup = nil }

    func read() -> Float? {
        guard let functions, let display = controllableDisplay(functions) else { return nil }
        var level: Float = 0
        guard functions.get(display, &level) == 0 else { return nil }
        return min(max(level, 0), 1)
    }

    func write(_ level: Float) -> Bool {
        guard let functions, let display = controllableDisplay(functions) else { return false }
        return functions.set(display, min(max(level, 0), 1)) == 0
    }

    /// The display found at the first use after a `refresh()`, nil when there is none: looking for it on every key
    /// press would list the displays each time.
    private func controllableDisplay(_ functions: Functions) -> CGDirectDisplayID? {
        if lookup == nil {
            lookup = Lookup(display: builtInDisplay().flatMap { functions.canChange?($0) ?? true ? $0 : nil })
        }
        return lookup?.display
    }

    /// The built-in display while it is on (not with the lid closed); external ones are not driven.
    private static func activeBuiltInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}
