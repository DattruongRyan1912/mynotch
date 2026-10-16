import Testing
@testable import PerformanceModule

@Suite struct SMCThermalReaderTests {
    /// A reader over `channel`; `opened` counts how often it was asked to open the connection.
    func reader(over channel: FakeSMCChannel?) -> (reader: SMCThermalReader, opened: OpenCount) {
        let opened = OpenCount()
        let reader = SMCThermalReader { opened.increment(); return channel }
        return (reader, opened)
    }

    @Test func readsThisMacsDieTemperaturesAndFans() async throws {
        let (reader, _) = reader(over: FakeSMCChannel())
        let snapshot = try #require(await reader.read())
        #expect(snapshot.cpu == ThisMacSMC.hottestCPU)
        #expect(snapshot.gpu == ThisMacSMC.hottestGPU)
        #expect(snapshot.soc == ThisMacSMC.hottestCPU)
        #expect(snapshot.fans.count == 2)
        let (first, second) = (snapshot.fans[0], snapshot.fans[1])
        #expect(first.index == 0 && second.index == 1)
        #expect(abs(first.rpm - 5230.2017) < 0.001)
        #expect(first.minRPM == 1200 && first.maxRPM == 5779)
        #expect(abs(second.rpm - 5656.1978) < 0.001)
        #expect(second.minRPM == 1200 && second.maxRPM == 6241)
    }

    @Test func onlyTheDieKeysCountAndTheLookAlikesDoNot() async throws {
        let channel = FakeSMCChannel()
        // Every die key reads 50 but one; TCMz (80.4), the PMU's TPD0 (53) and the rest of the look-alikes keep their values.
        for key in channel.allKeys where SMCThermalReaderTests.isDie(key) { channel.set(key, float: 50) }
        channel.set("Tp04", float: 62)
        let (reader, _) = reader(over: channel)
        let snapshot = try #require(await reader.read())
        #expect(snapshot.cpu == 62)
        #expect(snapshot.gpu == 50)
    }

    @Test func discoveryHappensOnceAndEachReadAsksOnlyForTheSensorsAndTheFans() async throws {
        let channel = FakeSMCChannel()
        let (reader, opened) = reader(over: channel)
        _ = await reader.read()
        let afterFirst = channel.counts.withLock { $0 }
        #expect(afterFirst.keyNames > 0)
        _ = await reader.read()
        _ = await reader.read()
        let afterThree = channel.counts.withLock { $0 }
        #expect(afterThree.keyNames == afterFirst.keyNames, "the key list is not walked again")
        #expect(afterThree.infos == afterFirst.infos, "no key is asked about again")
        let sensors = ThisMacSMC.cpuKeyCount + ThisMacSMC.gpuKeyCount
        let perRead = sensors + 2                                       // two fans' actual speed
        #expect(afterThree.reads - afterFirst.reads == 2 * perRead)
        #expect(opened.value == 1)
    }

    @Test func aNewReadSeesNewValues() async throws {
        let channel = FakeSMCChannel()
        let (reader, _) = reader(over: channel)
        _ = await reader.read()
        for key in channel.allKeys where SMCSensorCatalog.role(of: key) == .cpu { channel.set(key, float: 45) }
        for key in ["Tg04", "Tg05", "Tg0C", "Tg0D"] { channel.set(key, float: 52) }
        channel.set("F0Ac", float: 2400)
        let snapshot = try #require(await reader.read())
        #expect(snapshot.cpu == 45)
        #expect(snapshot.gpu == 52)
        #expect(snapshot.fans.first?.rpm == 2400)
    }

    @Test func aSensorThatReadsZeroIsLeftOutAndIfAllDoTheDieIsUnknown() async throws {
        let channel = FakeSMCChannel()
        let (reader, _) = reader(over: channel)
        _ = await reader.read()
        for key in ["Tg04", "Tg05", "Tg0C", "Tg0D"] { channel.set(key, float: 0) }
        let snapshot = try #require(await reader.read())
        #expect(snapshot.gpu == nil)
        #expect(snapshot.cpu == ThisMacSMC.hottestCPU)
        #expect(snapshot.soc == ThisMacSMC.hottestCPU)
    }

    @Test func aSensorThatCannotBeReadAnymoreIsLeftOut() async throws {
        let channel = FakeSMCChannel()
        let (reader, _) = reader(over: channel)
        _ = await reader.read()
        channel.remove("Tp0Q")
        let snapshot = try #require(await reader.read())
        #expect(try #require(snapshot.cpu) < ThisMacSMC.hottestCPU)
    }

    @Test func aMacWithNoFansShowsNone() async throws {
        let channel = FakeSMCChannel()
        channel.set("FNum", bytes: [0])
        let (reader, _) = reader(over: channel)
        let snapshot = try #require(await reader.read())
        #expect(snapshot.fans.isEmpty)
        #expect(snapshot.cpu != nil)
    }

    @Test func aFanWhoseSpeedCannotBeReadIsSkipped() async throws {
        let channel = FakeSMCChannel()
        let (reader, _) = reader(over: channel)
        _ = await reader.read()
        channel.remove("F0Ac")
        let snapshot = try #require(await reader.read())
        #expect(snapshot.fans.map(\.index) == [1])
    }

    @Test func aFanWithoutLimitsIsSkipped() async throws {
        let channel = FakeSMCChannel()
        channel.remove("F1Mx")
        let (reader, _) = reader(over: channel)
        let snapshot = try #require(await reader.read())
        #expect(snapshot.fans.map(\.index) == [0])
    }

    @Test func aMacWithNoDieSensorsStillShowsItsFans() async throws {
        let entries = ThisMacSMC.entries.filter { !SMCThermalReaderTests.isDie($0.key) }
        let (reader, _) = reader(over: FakeSMCChannel(entries))
        let snapshot = try #require(await reader.read())
        #expect(snapshot.cpu == nil && snapshot.gpu == nil && snapshot.soc == nil)
        #expect(snapshot.fans.count == 2)
    }

    @Test func nothingToShowIsNoReading() async {
        let entries = ThisMacSMC.entries.filter { !SMCThermalReaderTests.isDie($0.key) && !$0.key.hasPrefix("F") }
        let (reader, _) = reader(over: FakeSMCChannel(entries))
        #expect(await reader.read() == nil)
    }

    @Test func anSMCThatCannotBeOpenedIsNotAvailableAndIsNoReadingAndIsTriedAgainNextTime() async {
        let (reader, opened) = reader(over: nil)
        #expect(await reader.isAvailable() == false)
        #expect(await reader.read() == nil)
        #expect(opened.value == 2)
    }

    @Test func askingWhetherItIsAvailableOpensTheConnectionButDoesNotWalkTheKeys() async {
        let channel = FakeSMCChannel()
        let (reader, opened) = reader(over: channel)
        #expect(await reader.isAvailable())
        #expect(opened.value == 1)
        #expect(channel.counts.withLock { $0 } == FakeSMCChannel.Counts())
        _ = await reader.read()
        #expect(opened.value == 1, "the connection is kept")
        #expect(channel.counts.withLock { $0.keyNames } > 0)
    }

    @Test func aMacWithNothingToShowIsNotSearchedAgainAtEveryRead() async {
        let channel = FakeSMCChannel(ThisMacSMC.entries.filter { !SMCThermalReaderTests.isDie($0.key) && !$0.key.hasPrefix("F") })
        let (reader, _) = reader(over: channel)
        _ = await reader.read()
        let once = channel.counts.withLock { $0 }
        _ = await reader.read()
        #expect(channel.counts.withLock { $0 } == once)
    }

    @Test func shuttingDownLetsGoOfTheConnectionAndTheNextReadOpensAndDiscoversAgain() async throws {
        let channel = FakeSMCChannel()
        let (reader, opened) = reader(over: channel)
        _ = await reader.read()
        await reader.shutdown()
        let keyNames = channel.counts.withLock { $0.keyNames }
        _ = try #require(await reader.read())
        #expect(opened.value == 2)
        #expect(channel.counts.withLock { $0.keyNames } == 2 * keyNames)
    }

    static func isDie(_ key: String) -> Bool { SMCSensorCatalog.role(of: key) != nil }
}
