import Foundation

/// The one way to draw a window above the lock screen: a "space" at the level the lock screen uses, with the
/// window moved into it. No public API does this, so it is behind a protocol and every use is optional.
public protocol SkyLightShim: AnyObject {
    /// False when SkyLight or any function the shim needs is missing, e.g. after a macOS update. The other methods then do nothing.
    var isAvailable: Bool { get }
    /// Creates the space at the lock screen's level and shows it. Once per shim; later calls do nothing.
    func makeLockScreenSpace()
    /// Moves the window into the lock screen space and out of every other space.
    func attach(windowNumber: Int)
    func detach(windowNumber: Int)
}

/// `SkyLightShim` over the private SkyLight framework, loaded with `dlopen` and `dlsym` so nothing links against it.
///
/// The functions return codes that can be garbage even when they work, so no return value is ever checked:
/// a failure shows up as a missing widget, never as a crash or an error to handle.
public final class SystemSkyLightShim: SkyLightShim {
    static let libraryPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    /// `NotificationCenterAtScreenLock`: above the lock screen's own windows.
    static let lockScreenLevel: Int32 = 400
    /// Moves the window into the space and out of every other one.
    static let moveWindowOptions: Int32 = 7

    private struct Functions {
        let mainConnectionID: @convention(c) () -> Int32
        // The space and flag arguments are pointer-sized, so the call is right whichever width the library reads.
        let spaceCreate: @convention(c) (Int32, Int, UnsafeRawPointer?) -> UInt
        let setAbsoluteLevel: @convention(c) (Int32, Int, Int32) -> Int32
        let showSpaces: @convention(c) (Int32, CFArray) -> Int32
        let addWindowsAndRemoveFromSpaces: @convention(c) (Int32, Int, CFArray, Int32) -> Int32
        let removeWindowsFromSpaces: @convention(c) (Int32, CFArray, CFArray) -> Int32

        /// nil when any of the six is missing.
        init?(resolve: (String) -> UnsafeMutableRawPointer?) {
            guard let mainConnectionID = resolve("SLSMainConnectionID"),
                  let spaceCreate = resolve("SLSSpaceCreate"),
                  let setAbsoluteLevel = resolve("SLSSpaceSetAbsoluteLevel"),
                  let showSpaces = resolve("SLSShowSpaces"),
                  let addWindows = resolve("SLSSpaceAddWindowsAndRemoveFromSpaces"),
                  let removeWindows = resolve("SLSRemoveWindowsFromSpaces") else { return nil }
            self.mainConnectionID = unsafeBitCast(mainConnectionID, to: (@convention(c) () -> Int32).self)
            self.spaceCreate = unsafeBitCast(spaceCreate, to: (@convention(c) (Int32, Int, UnsafeRawPointer?) -> UInt).self)
            self.setAbsoluteLevel = unsafeBitCast(setAbsoluteLevel, to: (@convention(c) (Int32, Int, Int32) -> Int32).self)
            self.showSpaces = unsafeBitCast(showSpaces, to: (@convention(c) (Int32, CFArray) -> Int32).self)
            self.addWindowsAndRemoveFromSpaces = unsafeBitCast(addWindows, to: (@convention(c) (Int32, Int, CFArray, Int32) -> Int32).self)
            self.removeWindowsFromSpaces = unsafeBitCast(removeWindows, to: (@convention(c) (Int32, CFArray, CFArray) -> Int32).self)
        }
    }

    private let functions: Functions?
    private var space: (connection: Int32, id: Int)?

    public var isAvailable: Bool { functions != nil }

    public convenience init() {
        self.init(libraryPath: Self.libraryPath)
    }

    /// The library stays loaded for the life of the process, which the resolved functions rely on.
    convenience init(libraryPath: String) {
        let handle = dlopen(libraryPath, RTLD_LAZY | RTLD_LOCAL)
        self.init(resolve: { name in handle.flatMap { dlsym($0, name) } })
    }

    /// Resolves the symbols and calls none of them.
    init(resolve: (String) -> UnsafeMutableRawPointer?) {
        functions = Functions(resolve: resolve)
    }

    public func makeLockScreenSpace() {
        guard let functions, space == nil else { return }
        let connection = functions.mainConnectionID()
        // The id fits in 32 bits; the call reads the result at the width of a pointer and keeps only those bits.
        let id = Int(UInt32(truncatingIfNeeded: functions.spaceCreate(connection, 1, nil)))
        _ = functions.setAbsoluteLevel(connection, id, Self.lockScreenLevel)
        _ = functions.showSpaces(connection, [id] as CFArray)
        space = (connection, id)
    }

    public func attach(windowNumber: Int) {
        guard let functions, let space else { return }
        _ = functions.addWindowsAndRemoveFromSpaces(space.connection, space.id, [windowNumber] as CFArray, Self.moveWindowOptions)
    }

    public func detach(windowNumber: Int) {
        guard let functions, let space else { return }
        _ = functions.removeWindowsFromSpaces(space.connection, [windowNumber] as CFArray, [space.id] as CFArray)
    }
}
