import CoreGraphics
import Foundation
import Testing
@testable import SystemActivitiesModule

// The C stand-ins take the place of DisplayServices' functions, so nothing here reaches the private framework or a
// real display. They share one log and one level, so the tests that use them are in a serialized suite.
nonisolated(unsafe) private var displayLog: [String] = []
nonisolated(unsafe) private var displayLevel: Float = 0.5
nonisolated(unsafe) private var displayGetResult: Int32 = 0
nonisolated(unsafe) private var displayCanChange = true

private nonisolated func fakeGetBrightness(_ display: CGDirectDisplayID, _ level: UnsafeMutablePointer<Float>) -> Int32 {
    displayLog.append("get \(display)")
    level.pointee = displayLevel
    return displayGetResult
}

private nonisolated func fakeSetBrightness(_ display: CGDirectDisplayID, _ level: Float) -> Int32 {
    displayLog.append("set \(display) \(level)")
    displayLevel = level
    return 0
}

private nonisolated func fakeCanChangeBrightness(_ display: CGDirectDisplayID) -> Bool {
    displayLog.append("canChange \(display)")
    return displayCanChange
}

private func pointer<T>(_ function: T) -> UnsafeMutableRawPointer {
    unsafeBitCast(function, to: UnsafeMutableRawPointer.self)
}

private nonisolated let getName = "DisplayServicesGetBrightness"
private nonisolated let setName = "DisplayServicesSetBrightness"
private nonisolated let canChangeName = "DisplayServicesCanChangeBrightness"

@Suite(.serialized) struct BrightnessControlTests {
    init() {
        displayLog = []
        displayLevel = 0.5
        displayGetResult = 0
        displayCanChange = true
    }

    private func symbols(without missing: String? = nil) -> (String) -> UnsafeMutableRawPointer? {
        let all: [String: UnsafeMutableRawPointer] = [
            getName: pointer(fakeGetBrightness as @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32),
            setName: pointer(fakeSetBrightness as @convention(c) (CGDirectDisplayID, Float) -> Int32),
            canChangeName: pointer(fakeCanChangeBrightness as @convention(c) (CGDirectDisplayID) -> Bool),
        ]
        return { name in name == missing ? nil : all[name] }
    }

    private func control(
        resolve: @escaping (String) -> UnsafeMutableRawPointer?, builtIn: CGDirectDisplayID? = 7
    ) -> DisplayServicesBrightness {
        DisplayServicesBrightness(resolve: resolve, builtInDisplay: { builtIn })
    }

    @Test func readsAndSetsTheBuiltInDisplay() {
        let brightness = control(resolve: symbols())
        #expect(brightness.read() == 0.5)
        #expect(brightness.write(0.75))
        #expect(brightness.read() == 0.75)
        #expect(displayLog == ["canChange 7", "get 7", "canChange 7", "set 7 0.75", "canChange 7", "get 7"])
    }

    @Test func aLevelOutsideZeroToOneIsHeldWithinIt() {
        let brightness = control(resolve: symbols())
        #expect(brightness.write(1.5))
        #expect(displayLevel == 1)
        displayLevel = -0.2
        #expect(brightness.read() == 0)
    }

    @Test func creatingItResolvesAndCallsNothing() {
        nonisolated(unsafe) var lookups = 0
        _ = DisplayServicesBrightness(resolve: { _ in lookups += 1; return nil }, builtInDisplay: { 7 })
        #expect(lookups == 0)
        #expect(displayLog.isEmpty)
    }

    @Test(arguments: [getName, setName])
    func aMissingFunctionMakesItUnavailableAndTheKeysAreLeftAlone(missing: String) {
        let brightness = control(resolve: symbols(without: missing))
        #expect(brightness.read() == nil)
        #expect(!brightness.write(0.5))
        #expect(displayLog.isEmpty)
    }

    @Test func withoutTheOptionalCanChangeTheDisplayIsAssumedControllable() {
        let brightness = control(resolve: symbols(without: canChangeName))
        #expect(brightness.read() == 0.5)
        #expect(brightness.write(0.25))
        #expect(!displayLog.contains { $0.hasPrefix("canChange") })
    }

    @Test func aDisplayThatCannotChangeIsLeftAlone() {
        displayCanChange = false
        let brightness = control(resolve: symbols())
        #expect(brightness.read() == nil)
        #expect(!brightness.write(0.5))
        #expect(!displayLog.contains { $0.hasPrefix("get") || $0.hasPrefix("set") })
    }

    @Test func withoutABuiltInDisplayThereIsNothingToControl() {
        let brightness = control(resolve: symbols(), builtIn: nil)
        #expect(brightness.read() == nil)
        #expect(!brightness.write(0.5))
        #expect(displayLog.isEmpty)
    }

    @Test func aFailedReadIsNotALevel() {
        displayGetResult = 1
        #expect(control(resolve: symbols()).read() == nil)
    }
}
