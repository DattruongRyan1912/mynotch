import CoreAudio
import Foundation
import Testing
@testable import EqualizerAudio

@Suite struct TapRecipeTests {
    @Test func tapRecipeMutesWhenTappedAndExcludesSelf() {
        let description = TapRecipe.tapDescription(deviceUID: "speakers-uid", excluding: [4242])
        // MyNotch's own replay must never be heard by its own tap, or it would feed back.
        #expect(description.isExclusive)
        #expect(description.processes == [4242])
        // One device's first stream, so audio the app sent to that device is the audio that comes back to it.
        #expect(description.deviceUID == "speakers-uid")
        #expect(description.stream == 0)
        #expect(description.isPrivate)
        // The original is silenced while tapped, and comes back by itself when nobody reads the tap any more.
        #expect(description.muteBehavior == .mutedWhenTapped)
        #expect(description.name == "MyNotch EQ speakers-uid")
    }

    @Test func tapWithoutOwnProcessExcludesNobody() {
        let description = TapRecipe.tapDescription(deviceUID: "x", excluding: [])
        #expect(description.isExclusive)
        #expect(description.processes.isEmpty)
    }

    @Test func aggregateRunsOnThatDeviceAndTapsOnlyThatTap() throws {
        let recipe = TapRecipe.aggregate(deviceUID: "speakers-uid", tapUID: "tap-uid", aggregateUID: "aggregate-uid")
        #expect(recipe[kAudioAggregateDeviceUIDKey] as? String == "aggregate-uid")
        #expect(recipe[kAudioAggregateDeviceNameKey] as? String == "MyNotch EQ speakers-uid")
        #expect(recipe[kAudioAggregateDeviceMainSubDeviceKey] as? String == "speakers-uid")
        #expect(recipe[kAudioAggregateDeviceIsPrivateKey] as? Bool == true)
        #expect(recipe[kAudioAggregateDeviceIsStackedKey] as? Bool == false)
        // Start with the device rather than wait for the first tapped audio, so a denied tap still ends up silent, not stuck.
        #expect(recipe[kAudioAggregateDeviceTapAutoStartKey] as? Bool == false)

        let subdevices = try #require(recipe[kAudioAggregateDeviceSubDeviceListKey] as? [[String: Any]])
        #expect(subdevices.count == 1)
        #expect(subdevices[0][kAudioSubDeviceUIDKey] as? String == "speakers-uid")

        let taps = try #require(recipe[kAudioAggregateDeviceTapListKey] as? [[String: Any]])
        #expect(taps.count == 1)
        #expect(taps[0][kAudioSubTapUIDKey] as? String == "tap-uid")
        #expect(taps[0][kAudioSubTapDriftCompensationKey] as? Bool == true)
    }

    @Test func eachAggregateGetsItsOwnUID() {
        let one = TapRecipe.aggregate(deviceUID: "d", tapUID: "t")
        let two = TapRecipe.aggregate(deviceUID: "d", tapUID: "t")
        #expect(one[kAudioAggregateDeviceUIDKey] as? String != two[kAudioAggregateDeviceUIDKey] as? String)
    }
}
