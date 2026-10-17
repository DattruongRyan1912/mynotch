import FanHelperKit
import Foundation
import Testing
@testable import FanHelperDaemon

@Suite struct FanKeyWriterTests {
    /// Waiting costs nothing: the writer's clock is a fake that its own sleeps move.
    func writer(_ smc: FakeFanSMC = FakeFanSMC(), log: LogLines = LogLines()) throws -> FanKeyWriter {
        try FanKeyWriter(channel: smc, log: { log.add($0) }, timing: .fake(FakeClock()))
    }

    // MARK: Which keys

    @Test func onlyTheModeAndTheTargetOfAFanAreKeysItMayWrite() {
        for key in ["F0Md", "F1Md", "F0md", "F0Tg", "F7Tg", "F7Md"] { #expect(FanKeyWriter.isAllowedKey(key), "\(key)") }
        for key in ["Ftst", "F0Mn", "F0Mx", "F0Ac", "F8Md", "F8Tg", "FS! ", "F0MD", "F0tg", "FNum", "Tp00", "TC0P", "", "F0M", "F0Mdd", "F-1Tg"] {
            #expect(FanKeyWriter.isAllowedKey(key) == false, "\(key)")
        }
    }

    @Test func everyWriteGoesToAnAllowedKeyAndNothingElseIsEverWritten() throws {
        let smc = FakeFanSMC()
        let writer = try writer(smc)
        try writer.setManual(0, true)
        try writer.setTarget(0, rpm: 3000)
        try writer.setManual(1, true)
        try writer.setTarget(1, rpm: 4000)
        try writer.setManual(0, false)
        try writer.setManual(1, false)
        #expect(smc.writes.allSatisfy { FanKeyWriter.isAllowedKey($0.key) })
        #expect(smc.writes.count == 6)
    }

    // MARK: What is written

    @Test func theModeIsOneByteAndTheTargetALittleEndianFloat() throws {
        let smc = FakeFanSMC()
        let writer = try writer(smc)
        try writer.setManual(1, true)
        try writer.setTarget(1, rpm: 3200)
        try writer.setManual(1, false)
        #expect(smc.writes == [.mode(1, 1), .target(1, 3200), .mode(1, 0)])
        #expect(smc.writes[1].bytes == [0x00, 0x00, 0x48, 0x45], "3200.0 as a little-endian float")
    }

    @Test func aWriteIsReadBackFromTheSMC() throws {
        let smc = FakeFanSMC()
        let writer = try writer(smc)
        try writer.setManual(0, true)
        try writer.setTarget(0, rpm: 3333.4)
        #expect(smc.mode(fan: 0) == 1)
        #expect(abs((smc.target(fan: 0) ?? 0) - 3333.4) < 0.5)
    }

    // MARK: What is refused

    @Test func aSpeedThatIsNotANumberOrIsNegativeIsRefusedBeforeAnythingIsWritten() throws {
        let smc = FakeFanSMC()
        let writer = try writer(smc)
        for rpm in [Double.nan, .infinity, -.infinity, -1] {
            #expect(throws: FanWriteError.notAFiniteSpeed) { try writer.setTarget(0, rpm: rpm) }
        }
        #expect(smc.writes.isEmpty)
    }

    @Test func aFanThatDoesNotExistIsRefusedBeforeAnythingIsWritten() throws {
        let smc = FakeFanSMC(fans: 2)
        let writer = try writer(smc)
        for fan in [-1, 2, 7, 99] {
            #expect(throws: FanWriteError.noSuchFan) { try writer.setManual(fan, true) }
            #expect(throws: FanWriteError.noSuchFan) { try writer.setTarget(fan, rpm: 3000) }
        }
        #expect(smc.writes.isEmpty)
    }

    @Test func theNumberOfFansIsWhatTheSMCSaysAndAtMostEight() throws {
        #expect(try writer(FakeFanSMC(fans: 2)).fanCount == 2)
        #expect(try writer(FakeFanSMC(fans: 9)).fanCount == 8, "a count past eight is not followed")
    }

    @Test func aMacWithoutFansOrWithoutTheRightKeysCannotBeWrittenTo() {
        let none = FakeFanSMC(fans: 1)
        none.replace("FNum", type: "ui8 ", bytes: [0])
        #expect(throws: FanWriteError.missingKey("FNum")) { try FanKeyWriter(channel: none) }

        let noMode = FakeFanSMC()
        noMode.remove("F1Md")
        #expect(throws: FanWriteError.missingKey("F1Md")) { try FanKeyWriter(channel: noMode) }

        let noTarget = FakeFanSMC()
        noTarget.remove("F0Tg")
        #expect(throws: FanWriteError.missingKey("F0Tg")) { try FanKeyWriter(channel: noTarget) }
    }

    @Test func aKeyOfAnotherTypeThanTheSMCUsuallyHasIsNotWritten() {
        let wrongMode = FakeFanSMC()
        wrongMode.replace("F0Md", type: "flt ", bytes: [0, 0, 0, 0])
        #expect(throws: FanWriteError.missingKey("F0Md")) { try FanKeyWriter(channel: wrongMode) }

        let wrongTarget = FakeFanSMC()
        wrongTarget.replace("F0Tg", type: "ui16", bytes: [0, 0])
        #expect(throws: FanWriteError.wrongType("F0Tg")) { try FanKeyWriter(channel: wrongTarget) }
        #expect(wrongTarget.writes.isEmpty)
    }

    @Test func aChipThatSpellsTheModeKeyInLowercaseIsFound() throws {
        let smc = FakeFanSMC()
        smc.remove("F0Md")
        smc.replace("F0md", type: "ui8 ", bytes: [0])
        let writer = try writer(smc)
        try writer.setManual(0, true)
        #expect(smc.writes == [FakeFanSMC.Write(key: "F0md", bytes: [1])])
    }

    // MARK: Read-back

    @Test func aWriteThatDoesNotReadBackAsWrittenIsAnError() throws {
        let smc = FakeFanSMC()
        let writer = try writer(smc)
        smc.refuse("F0Md", code: 0x82)
        #expect(throws: FanWriteError.refused("F0Md", 0x82)) { try writer.setManual(0, true) }
    }

    @Test func aWriteThatTheSMCAnswersWithAnErrorButAppliedIsAcceptedBecauseItReadsBack() throws {
        let smc = FakeFanSMC()
        let writer = try writer(smc)
        smc.refuse("F0Tg", code: 0x87, appliesAnyway: true)
        try writer.setTarget(0, rpm: 3000)
        #expect(abs((smc.target(fan: 0) ?? 0) - 3000) < 0.5)
    }

    @Test func anOKAnswerWithAnotherValueReadingBackIsAnError() throws {
        // The firmware acknowledges the write and quietly keeps the old value: what reads back is not what was written.
        let strict = try FanKeyWriter(channel: StubbornSMC(FakeFanSMC()), timing: .fake(FakeClock()))
        #expect(throws: FanWriteError.readBackDiffers("F0Tg")) { try strict.setTarget(0, rpm: 3000) }
        #expect(throws: FanWriteError.readBackDiffers("F0Md")) { try strict.setManual(0, true) }
    }

    // MARK: Log

    @Test func eachWriteIsLoggedWithTheFanAndTheModeOrSpeedAndNothingElse() throws {
        let log = LogLines()
        let writer = try writer(FakeFanSMC(), log: log)
        try writer.setManual(0, true)
        try writer.setTarget(0, rpm: 3200.4)
        try writer.setManual(0, false)
        #expect(log.all == ["F0Md=1 read back after 0 ms (1)", "F0Tg=3200 read back after 0 ms (3200)", "F0Md=0 read back after 0 ms (0)"])
    }

    @Test func aWriteThatFailedIsNotLoggedAsDone() throws {
        let log = LogLines()
        let smc = FakeFanSMC()
        let writer = try writer(smc, log: log)
        smc.refuse("F0Md")
        _ = try? writer.setManual(0, true)
        #expect(log.all == ["F0Md=1 result 130 and reads 0"], "said so, and not as a write that was read back")
    }

    /// The real writer needs root: a test is never root, so it cannot be made, and no test can write to the real SMC.
    @Test func theRealWriterCannotBeMadeByAProcessThatIsNotRoot() {
        guard geteuid() != 0 else { return }
        #expect(AppleSMCWriter() == nil)
    }
}

/// An SMC whose writes are acknowledged and ignored: what is read back is never what was written.
struct StubbornSMC: SMCWriteChannel {
    let base: FakeFanSMC
    init(_ base: FakeFanSMC) { self.base = base }
    func keyName(at index: Int) -> String? { base.keyName(at: index) }
    func info(of key: String) -> SMCKeyInfo? { base.info(of: key) }
    func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]? { base.bytes(of: key, info: info) }
    func write(_ key: String, info: SMCKeyInfo, bytes: [UInt8]) -> SMCWriteResult { .ok }
}
