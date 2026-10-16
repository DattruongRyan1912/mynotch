import Testing
@testable import PerformanceModule

@Suite struct SMCChannelTests {
    /// The SMC's request is 80 bytes with C's padding; Swift does not pad `SMCKeyInfoData` from 9 to 12 bytes by itself, and a
    /// request of the wrong size makes the call fail (the TH0 probe found out the hard way).
    @Test func theRequestHasTheLayoutOfTheCStruct() {
        #expect(MemoryLayout<SMCParamStruct>.size == 80)
        #expect(MemoryLayout<SMCParamStruct>.stride == 80)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.key) == 0)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.vers) == 4)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.pLimitData) == 12)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo) == 28)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.result) == 40)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.status) == 41)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data8) == 42)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data32) == 44)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.bytes) == 48)
    }

    @Test func theKeyInfoIsTwelveBytesLikeInC() {
        #expect(MemoryLayout<SMCKeyInfoData>.size == 12)
    }

    /// The module can only read: the three commands are the SMC's read key, key at index and key info. There is no case
    /// for the write command (6), so no code path can send it.
    @Test func theOnlyCommandsAreReads() {
        #expect(SMCCommand.allCases.map(\.rawValue).sorted() == [5, 8, 9])
        #expect(SMCCommand(rawValue: 6) == nil)
    }
}
