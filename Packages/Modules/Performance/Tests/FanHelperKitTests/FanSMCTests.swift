import Testing
@testable import FanHelperKit

@Suite struct FanSMCTests {
    @Test func readsBothFansOfThisMac() {
        let fans = FanSMC.readFans(on: FanKeysChannel())
        #expect(fans.map(\.index) == [0, 1])
        #expect(fans.map(\.minRPM) == [1200, 1200] && fans.map(\.maxRPM) == [5779, 6241])
        #expect(fans.map(\.mode) == [0, 0])
        #expect(fans.map(\.target) == [5235, 5653])
    }

    @Test func aFanMissingItsSpeedOrLimitsIsLeftOut() {
        for key in ["F0Ac", "F0Mn", "F0Mx"] {
            var entries = FanKeysChannel.thisMac
            entries[key] = nil
            #expect(FanSMC.readFans(on: FanKeysChannel(entries)).map(\.index) == [1], "\(key)")
        }
    }

    @Test func aFanWhoseSpeedIsNotAFloatIsLeftOut() {
        var entries = FanKeysChannel.thisMac
        entries["F1Ac"] = ("ui16", [0x15, 0x00])
        #expect(FanSMC.readFans(on: FanKeysChannel(entries)).map(\.index) == [0])
    }

    @Test func aFanMissingItsModeOrTargetIsStillThereWithThemUnknown() {
        var entries = FanKeysChannel.thisMac
        entries["F0Md"] = nil
        entries["F0Tg"] = nil
        let fan = FanSMC.readFans(on: FanKeysChannel(entries)).first
        #expect(fan?.index == 0)
        #expect(fan?.mode == FanHelperFan.unknown && fan?.target == FanHelperFan.unknown)
    }

    @Test func noFanCountIsNoFans() {
        var entries = FanKeysChannel.thisMac
        entries["FNum"] = nil
        #expect(FanSMC.readFans(on: FanKeysChannel(entries)).isEmpty)
    }

    @Test func aSillyFanCountIsNotFollowed() {
        var entries = FanKeysChannel.thisMac
        entries["FNum"] = ("ui8 ", [255])
        #expect(FanSMC.readFans(on: FanKeysChannel(entries)).count == 2, "only the fans that exist are returned")
    }
}
