import Testing
@testable import PerformanceModule

/// Byte fixtures are the bytes this Mac's SMC returned in the TH0 probe (MacBookPro18,3).
@Suite struct SMCCodecTests {
    @Test func floatsAreLittleEndian() throws {
        #expect(SMCValue.number(type: "flt ", bytes: [0x00, 0x00, 0x96, 0x44]) == 1200)               // F0Mn
        #expect(SMCValue.number(type: "flt ", bytes: [0x00, 0x98, 0xb4, 0x45]) == 5779)               // F0Mx
        let actual = try #require(SMCValue.number(type: "flt ", bytes: [0xb5, 0x4d, 0xad, 0x45]))      // F0Ac
        #expect(abs(actual - 5545.7134) < 0.001)
        let die = try #require(SMCValue.number(type: "flt ", bytes: [0xcd, 0x7d, 0x7d, 0x42]))         // Tp00
        #expect(abs(die - 63.372852) < 0.0001)
    }

    @Test func unsignedIntegersAreBigEndian() {
        #expect(SMCValue.number(type: "ui32", bytes: [0x00, 0x00, 0x08, 0x03]) == 2051)              // #KEY
        #expect(SMCValue.number(type: "ui8 ", bytes: [0x02]) == 2)                                     // FNum
        #expect(SMCValue.number(type: "ui16", bytes: [0x00, 0x04]) == 4)                               // F0Fc
        #expect(SMCValue.number(type: "ui16", bytes: [0x01, 0x02]) == 258)
    }

    @Test func aValueWithTheWrongNumberOfBytesIsNotANumber() {
        #expect(SMCValue.number(type: "flt ", bytes: [0x00, 0x00, 0x96]) == nil)
        #expect(SMCValue.number(type: "ui32", bytes: [0x08, 0x03]) == nil)
        #expect(SMCValue.number(type: "ui8 ", bytes: []) == nil)
    }

    @Test func aTypeTheModuleDoesNotReadIsNotANumber() {
        #expect(SMCValue.number(type: "ioft", bytes: [0, 0, 0, 0, 0, 0, 0, 0]) == nil)               // TG0H
        #expect(SMCValue.number(type: "hex_", bytes: [0, 0, 0, 0]) == nil)                            // FBAD
        #expect(SMCValue.number(type: "ch8*", bytes: [0x41]) == nil)
    }

    @Test func aFloatThatIsNotFiniteIsNotANumber() {
        #expect(SMCValue.number(type: "flt ", bytes: [0x00, 0x00, 0xc0, 0x7f]) == nil)               // NaN
        #expect(SMCValue.number(type: "flt ", bytes: [0x00, 0x00, 0x80, 0x7f]) == nil)               // +infinity
    }

    @Test func aZeroFloatIsZero() {
        #expect(SMCValue.number(type: "flt ", bytes: [0, 0, 0, 0]) == 0)                              // TVMD, Ta00 and friends
    }

    @Test func keyNamesAreFourCharacterCodes() {
        #expect(SMCKey.code("F0Ac") == 0x4630_4163)
        #expect(SMCKey.code("#KEY") == 0x234b_4559)
        #expect(SMCKey.name(0x4630_4163) == "F0Ac")
        #expect(SMCKey.code("FNum").map(SMCKey.name) == "FNum")
    }

    @Test func aNameThatIsNotFourCharactersIsNotAKey() {
        #expect(SMCKey.code("F0A") == nil)
        #expect(SMCKey.code("F0Acc") == nil)
        #expect(SMCKey.code("") == nil)
    }
}
