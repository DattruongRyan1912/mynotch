import Foundation
import Testing
@testable import SystemActivitiesModule

/// A stand-in for CoreBrightness' `KeyboardBrightnessClient`, with the three selectors the control looks for.
@objc private final class FakeKeyboardBrightnessClient: NSObject {
    var ids: [NSNumber] = [95]
    var level: Float = 0.5
    var setResult = true
    var calls: [String] = []

    @objc(copyKeyboardBacklightIDs) func copyKeyboardBacklightIDs() -> NSArray {
        calls.append("ids")
        return ids as NSArray
    }

    @objc(brightnessForKeyboard:) func brightness(forKeyboard id: UInt64) -> Float {
        calls.append("get \(id)")
        return level
    }

    @objc(setBrightness:forKeyboard:) func setBrightness(_ brightness: Float, forKeyboard id: UInt64) -> Bool {
        calls.append("set \(id) \(brightness)")
        level = brightness
        return setResult
    }
}

/// A client missing the setter.
@objc private final class ReadOnlyKeyboardClient: NSObject {
    @objc(copyKeyboardBacklightIDs) func copyKeyboardBacklightIDs() -> NSArray { [95] }
    @objc(brightnessForKeyboard:) func brightness(forKeyboard id: UInt64) -> Float { 0.5 }
}

@Suite struct KeyboardLightControlTests {
    @Test func readsAndSetsTheFirstKeyboardWithABacklight() {
        let client = FakeKeyboardBrightnessClient()
        client.ids = [95, 96]
        let light = CoreBrightnessKeyboardLight(makeClient: { client })
        #expect(light.read() == 0.5)
        #expect(light.write(0.25))
        #expect(client.level == 0.25)
        #expect(client.calls == ["ids", "get 95", "ids", "set 95 0.25"])
    }

    @Test func aLevelOutsideZeroToOneIsHeldWithinIt() {
        let client = FakeKeyboardBrightnessClient()
        let light = CoreBrightnessKeyboardLight(makeClient: { client })
        #expect(light.write(2))
        #expect(client.level == 1)
    }

    @Test func aRefusedWriteIsReported() {
        let client = FakeKeyboardBrightnessClient()
        client.setResult = false
        #expect(!CoreBrightnessKeyboardLight(makeClient: { client }).write(0.5))
    }

    @Test func creatingItMakesNoClientAndCallsNothing() {
        nonisolated(unsafe) var made = 0
        _ = CoreBrightnessKeyboardLight(makeClient: { made += 1; return nil })
        #expect(made == 0)
    }

    @Test func theClientIsMadeOnceNoMatterHowOftenItIsUsed() {
        nonisolated(unsafe) var made = 0
        let client = FakeKeyboardBrightnessClient()
        let light = CoreBrightnessKeyboardLight(makeClient: { made += 1; return client })
        _ = light.read()
        _ = light.read()
        _ = light.write(0.5)
        #expect(made == 1)
    }

    @Test func aMissingClassMakesItUnavailableAndTheKeysAreLeftAlone() {
        let light = CoreBrightnessKeyboardLight(makeClient: { nil })
        #expect(light.read() == nil)
        #expect(!light.write(0.5))
    }

    @Test func aClientWithoutAMethodItNeedsMakesItUnavailable() {
        let light = CoreBrightnessKeyboardLight(makeClient: { ReadOnlyKeyboardClient() })
        #expect(light.read() == nil)
        #expect(!light.write(0.5))
    }

    @Test func aMacWithoutABacklitKeyboardHasNothingToControl() {
        let client = FakeKeyboardBrightnessClient()
        client.ids = []
        let light = CoreBrightnessKeyboardLight(makeClient: { client })
        #expect(light.read() == nil)
        #expect(!light.write(0.5))
        #expect(client.calls == ["ids", "ids"])
    }

    @Test(arguments: [-1.0, 1.5] as [Float])
    func aNonsenseLevelIsNotALevel(level: Float) {
        let client = FakeKeyboardBrightnessClient()
        client.level = level
        #expect(CoreBrightnessKeyboardLight(makeClient: { client }).read() == nil)
    }
}
