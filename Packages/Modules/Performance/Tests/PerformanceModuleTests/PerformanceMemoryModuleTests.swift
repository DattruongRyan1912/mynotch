import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import PerformanceModule

/// The memory half of the module: what each way of looking at it makes the module read.
@Suite struct PerformanceMemoryModuleTests {
    typealias Fixture = PerformanceModuleTests.Fixture

    @Test func theOpenTabReadsTheTemperaturesAndTheMemoryAndListsTheFiveHeaviestProcesses() async {
        let f = await Fixture()
        f.appear()
        await settle { f.module.state.processes.count == 5 }
        #expect(await f.reads() == 1)
        #expect(await f.memory.limits == [5])
        await settle { !f.module.isReading }
        #expect(f.module.state.usage == FakeMemoryReader.usage)
        #expect(f.module.state.thermal == FakeThermalReader.warm)
        #expect(f.module.state.processes.map(\.name) == ["Safari", "Xcode", "python3.11", "Slack", "Mail"])
        #expect(f.module.state.processes.map(\.size) == ["4 GB", "3 GB", "2 GB", "1 GB", "512 MB"])
        #expect(f.module.state.processes.map(\.id) == [500, 501, 502, 503, 504])
    }

    @Test func theTabReadsTheMemoryEveryTwoSecondsToo() async {
        let f = await Fixture()
        f.appear()
        await settle { await f.memoryReads() == 1 }
        f.advance(2)
        await settle { await f.memoryReads() == 2 }
        #expect(await f.memory.limits == [5, 5])
        #expect(await f.reads() == 2)
    }

    @Test func closingTheTabStopsReadingTheMemoryAndDropsWhatItShowed() async {
        let f = await Fixture()
        f.appear()
        await settle { f.module.state.processes.count == 5 }
        f.disappear()
        #expect(f.harness.scheduler.pendingCount == 0)
        #expect(f.module.state.thermal == nil)
        #expect(f.module.state.usage == nil)
        #expect(f.module.state.processes.isEmpty)
        f.advance(30)
        await idle()
        #expect(await f.memoryReads() == 1)
    }

    @Test func aReadThatFinishesAfterTheLastTabWentKeepsNothing() async {
        let f = await Fixture()
        await f.reader.hold()
        f.appear()
        await settle { await f.reads() == 1 }
        f.disappear()
        await f.reader.release()
        await settle { !f.module.isReading }
        #expect(f.module.state.thermal == nil)
        #expect(f.module.state.usage == nil)
        #expect(f.module.state.processes.isEmpty)
        #expect(f.harness.scheduler.pendingCount == 0)
    }

    @Test func aMemoryReadThatFailsKeepsTheLastNumbers() async {
        let f = await Fixture()
        f.appear()
        await settle { f.module.state.usage != nil }
        await f.memory.answer(with: MemorySnapshot(usage: nil, processes: []))
        f.advance(2)
        await settle { await f.memoryReads() == 2 }
        await settle { !f.module.isReading }
        await settle { !f.module.isReading }
        #expect(f.module.state.usage == FakeMemoryReader.usage)
    }

    // MARK: Strip

    @Test func theMemoryStripAloneReadsOnlyTheMemoryAndNoProcesses() async {
        let f = await Fixture(memoryStrip: true)
        await settle { await f.memoryReads() == 1 }
        f.advance(2)
        await settle { await f.memoryReads() == 2 }
        #expect(await f.memory.limits == [0, 0])
        #expect(await f.reads() == 0, "nobody asked for the temperature")
        await settle { !f.module.isReading }
        #expect(f.module.state.usage == FakeMemoryReader.usage)
        #expect(f.module.state.processes.isEmpty)
        #expect(f.module.state.thermal == nil)
    }

    @Test func theTemperatureStripAloneReadsNoMemory() async {
        let f = await Fixture(strip: true)
        await settle { await f.reads() == 1 }
        f.advance(2)
        await settle { await f.reads() == 2 }
        #expect(await f.memoryReads() == 0)
        #expect(f.module.state.usage == nil)
    }

    @Test func bothStripsReadBothAndStillNoProcesses() async {
        let f = await Fixture(strip: true, memoryStrip: true)
        await settle { await f.memoryReads() == 1 }
        #expect(await f.reads() == 1)
        #expect(await f.memory.limits == [0])
        #expect(f.module.state.processes.isEmpty)
    }

    @Test func aTabOpenOverAMemoryStripListsTheProcessesAndClosingItStopsTheList() async {
        let f = await Fixture(memoryStrip: true)
        await settle { await f.memoryReads() == 1 }
        f.appear()
        f.advance(2)
        await settle { f.module.state.processes.count == 5 }
        #expect(await f.memory.limits.last == 5)
        f.disappear()
        #expect(f.module.state.processes.isEmpty)
        #expect(f.module.state.usage == FakeMemoryReader.usage, "the strip still shows it")
        f.advance(2)
        await settle { await f.memoryReads() == 3 }
        #expect(await f.memory.limits.last == 0)
        #expect(f.harness.scheduler.pendingCount == 1)
    }

    @Test func aTemperatureStripKeepsItsNumbersWhenTheTabCloses() async {
        let f = await Fixture(strip: true)
        f.appear()
        await settle { f.module.state.usage != nil }
        f.disappear()
        await settle { !f.module.isReading }
        #expect(f.module.state.thermal == FakeThermalReader.warm)
        #expect(f.module.state.usage == nil, "nothing shows the memory now")
    }

    @Test func theMemoryStripIsALowPriorityActivityThatSaysWhatItShows() async {
        let f = await Fixture(memoryStrip: true)
        let entry = f.harness.activities.current
        #expect(entry?.id == "performance/strip")
        #expect(entry?.activity.priority == .low)
        #expect(entry?.activity.summary == "Dung lượng RAM")
        #expect(f.module.state.stripMemory && !f.module.state.stripTemperature)
    }

    @Test func bothStripsAreOneActivityThatSaysBoth() async {
        let f = await Fixture(strip: true, memoryStrip: true)
        #expect(f.harness.activities.entries.map(\.id) == ["performance/strip"])
        #expect(f.harness.activities.current?.activity.summary == "Nhiệt độ SoC và RAM")
    }

    @Test func changingWhatTheStripShowsRepublishesItOnceAndTurningBothOffClearsIt() async {
        let f = await Fixture(strip: true)
        #expect(f.harness.activities.current?.activity.summary == "Nhiệt độ SoC")
        f.harness.settings.set(true, for: PerformanceModuleTests.memoryStripKey)
        await settle { f.harness.activities.current?.activity.summary == "Nhiệt độ SoC và RAM" }
        #expect(f.harness.activities.current?.activity.summary == "Nhiệt độ SoC và RAM")
        f.harness.settings.set(false, for: PerformanceModuleTests.stripKey)
        await settle { f.harness.activities.current?.activity.summary == "Dung lượng RAM" }
        #expect(f.harness.activities.current?.activity.summary == "Dung lượng RAM")
        f.harness.settings.set(false, for: PerformanceModuleTests.memoryStripKey)
        await settle { f.harness.activities.current == nil }
        #expect(f.harness.activities.current == nil)
        await settle { f.harness.scheduler.pendingCount == 0 }
        #expect(f.harness.scheduler.pendingCount == 0)
    }

    @Test func theMemoryStripIsPublishedOnceNotAtEveryRead() async {
        let f = await Fixture(memoryStrip: true)
        await settle { await f.memoryReads() == 1 }
        await settle { !f.module.isReading }
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = f.harness.activities.current } onChange: { changes += 1 }
        for expected in 2...4 {
            f.advance(2)
            await settle { await f.memoryReads() == expected }
            await settle { !f.module.isReading }
        }
        #expect(changes == 0)
    }

    @Test func theMemoryStripNeverTakesTheNotchFromMusic() async {
        let f = await Fixture(memoryStrip: true)
        let music = LiveActivity(id: "nowPlaying", priority: .normal, leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()))
        f.harness.activities.set(music, from: "media")
        #expect(f.harness.activities.current?.id == "media/nowPlaying")
    }

    @Test func disablingTheModuleClearsTheMemoryToo() async {
        let f = await Fixture(memoryStrip: true)
        f.appear()
        await settle { f.module.state.processes.count == 5 }
        await f.harness.registry.setEnabled(false, for: "performance")
        #expect(f.module.state.usage == nil && f.module.state.processes.isEmpty)
        #expect(f.harness.activities.current == nil)
        #expect(f.harness.scheduler.pendingCount == 0)
    }

    // MARK: Settings

    @Test func bothStripSettingsAreOffUntilTheUserTurnsThemOn() throws {
        let harness = RegistryHarness([PerformanceModule(thermal: FakeThermalReader(), memory: FakeMemoryReader(), now: { .now })])
        let environment = try #require(harness.settingsEnvironment(for: "performance"))
        let keys = PerformanceSettingsKeys(environment.settings)
        #expect(keys.stripTemperature.name == "module.performance.stripTemperature")
        #expect(keys.stripMemory.name == "module.performance.stripMemory")
        #expect(environment.settings.value(keys.stripTemperature) == false)
        #expect(environment.settings.value(keys.stripMemory) == false)
    }
}
