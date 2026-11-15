import Foundation
import Testing
@testable import NotchUI

// The C stand-ins below take the place of SkyLight's functions, so nothing here reaches the private framework.
// They share one log and one space id, so the tests that use them are in a serialized suite.
nonisolated(unsafe) private var skyLightLog: [String] = []
nonisolated(unsafe) private var fakeSpaceID: UInt64 = 123

private nonisolated func fakeMainConnectionID() -> Int32 {
    skyLightLog.append("connection")
    return 9
}

private nonisolated func fakeSpaceCreate(_ connection: Int32, _ flags: Int, _ options: UnsafeRawPointer?) -> UInt64 {
    skyLightLog.append("create \(connection) \(flags) \(options == nil ? "nil" : "options")")
    return fakeSpaceID
}

private nonisolated func fakeSetAbsoluteLevel(_ connection: Int32, _ space: UInt64, _ level: Int32) -> Int32 {
    skyLightLog.append("level \(connection) \(space) \(level)")
    return 0
}

private nonisolated func fakeShowSpaces(_ connection: Int32, _ spaces: CFArray) -> Int32 {
    skyLightLog.append("show \(connection) \(numbers(spaces))")
    return 0
}

private nonisolated func fakeAddWindows(_ connection: Int32, _ space: UInt64, _ windows: CFArray, _ options: Int32) -> Int32 {
    skyLightLog.append("add \(connection) \(space) \(numbers(windows)) \(options)")
    return 0
}

private nonisolated func fakeRemoveWindows(_ connection: Int32, _ windows: CFArray, _ spaces: CFArray) -> Int32 {
    skyLightLog.append("remove \(connection) \(numbers(windows)) \(numbers(spaces))")
    return 0
}

private nonisolated func numbers(_ array: CFArray) -> [Int] {
    (array as? [NSNumber])?.map(\.intValue) ?? []
}

private func pointer<T>(_ function: T) -> UnsafeMutableRawPointer {
    unsafeBitCast(function, to: UnsafeMutableRawPointer.self)
}

private nonisolated let symbolNames = [
    "SLSMainConnectionID", "SLSSpaceCreate", "SLSSpaceSetAbsoluteLevel",
    "SLSShowSpaces", "SLSSpaceAddWindowsAndRemoveFromSpaces", "SLSRemoveWindowsFromSpaces",
]

/// Pointers that are never called: enough for `isAvailable`, which must not call into the library.
private func inertSymbols(except missing: String? = nil) -> (String) -> UnsafeMutableRawPointer? {
    { name in name == missing ? nil : UnsafeMutableRawPointer(bitPattern: 0x10) }
}

@Suite(.serialized) struct SkyLightShimTests {
    @Test func aLibraryThatCannotBeLoadedIsUnavailableAndEverythingIsANoOp() {
        let shim = SystemSkyLightShim(libraryPath: "/nonexistent/SkyLight.framework/SkyLight")
        #expect(!shim.isAvailable)
        shim.makeLockScreenSpace()
        shim.attach(windowNumber: 5)
        shim.detach(windowNumber: 5)
    }

    @Test func allSixSymbolsMakeItAvailable() {
        #expect(SystemSkyLightShim(resolve: inertSymbols()).isAvailable)
    }

    @Test(arguments: symbolNames)
    func aMissingSymbolMakesItUnavailable(missing: String) {
        let shim = SystemSkyLightShim(resolve: inertSymbols(except: missing))
        #expect(!shim.isAvailable)
        shim.makeLockScreenSpace()
        shim.attach(windowNumber: 5)
        shim.detach(windowNumber: 5)
    }

    private func shimWithFakeFunctions() -> SystemSkyLightShim {
        skyLightLog = []
        let functions: [String: UnsafeMutableRawPointer] = [
            "SLSMainConnectionID": pointer(fakeMainConnectionID as @convention(c) () -> Int32),
            "SLSSpaceCreate": pointer(fakeSpaceCreate as @convention(c) (Int32, Int, UnsafeRawPointer?) -> UInt64),
            "SLSSpaceSetAbsoluteLevel": pointer(fakeSetAbsoluteLevel as @convention(c) (Int32, UInt64, Int32) -> Int32),
            "SLSShowSpaces": pointer(fakeShowSpaces as @convention(c) (Int32, CFArray) -> Int32),
            "SLSSpaceAddWindowsAndRemoveFromSpaces": pointer(fakeAddWindows as @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32),
            "SLSRemoveWindowsFromSpaces": pointer(fakeRemoveWindows as @convention(c) (Int32, CFArray, CFArray) -> Int32),
        ]
        return SystemSkyLightShim(resolve: { functions[$0] })
    }

    @Test func callsReachSkyLightInOrder() {
        fakeSpaceID = 123
        let shim = shimWithFakeFunctions()
        #expect(shim.isAvailable)
        #expect(skyLightLog.isEmpty)

        // Attaching before there is a space does nothing.
        shim.attach(windowNumber: 77)
        #expect(skyLightLog.isEmpty)

        shim.makeLockScreenSpace()
        shim.makeLockScreenSpace()
        shim.attach(windowNumber: 77)
        shim.detach(windowNumber: 77)
        #expect(skyLightLog == [
            "connection", "create 9 1 nil", "level 9 123 400", "show 9 [123]",
            "add 9 123 [77] 7", "remove 9 [77] [123]",
        ])
    }

    @Test func aSpaceIdWiderThan32BitsIsPassedBackWhole() {
        fakeSpaceID = 0x1_0000_0007
        let shim = shimWithFakeFunctions()
        shim.makeLockScreenSpace()
        shim.attach(windowNumber: 77)
        shim.detach(windowNumber: 77)
        #expect(skyLightLog == [
            "connection", "create 9 1 nil", "level 9 4294967303 400", "show 9 [4294967303]",
            "add 9 4294967303 [77] 7", "remove 9 [77] [4294967303]",
        ])
    }
}
