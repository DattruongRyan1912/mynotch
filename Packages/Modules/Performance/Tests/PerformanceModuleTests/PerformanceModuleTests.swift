import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import PerformanceModule

@Suite struct PerformanceModuleTests {
    static let stripKey = SettingKey("module.performance.stripTemperature", default: false)
    static let memoryStripKey = SettingKey("module.performance.stripMemory", default: false)

    struct Fixture {
        let module: PerformanceModule
        let reader: FakeThermalReader
        let memory: FakeMemoryReader
        let harness: RegistryHarness
        let clock: TestClock

        /// `strip` turns the temperature strip on before the module starts, `memoryStrip` the memory one.
        @MainActor init(
            _ reader: FakeThermalReader = FakeThermalReader(), memory: FakeMemoryReader = FakeMemoryReader(),
            strip: Bool = false, memoryStrip: Bool = false
        ) async {
            let clock = TestClock()
            let module = PerformanceModule(thermal: reader, memory: memory, now: { clock.date })
            let harness = RegistryHarness([module])
            if strip { harness.settings.set(true, for: PerformanceModuleTests.stripKey) }
            if memoryStrip { harness.settings.set(true, for: PerformanceModuleTests.memoryStripKey) }
            await harness.registry.bootstrap()
            (self.module, self.reader, self.memory, self.harness, self.clock) = (module, reader, memory, harness, clock)
        }

        /// A tab on screen; `disappear` is what removing it does.
        func appear() { module.actions.appeared() }
        func disappear() { module.actions.disappeared() }

        /// Moves the scheduler's time and the module's clock together, once the read in flight (if any) has finished and
        /// scheduled the next one: a clock moved before that moves nothing.
        @MainActor func advance(_ seconds: Int) async {
            await settle { !module.isReading }
            clock.date = clock.date.addingTimeInterval(TimeInterval(seconds))
            harness.scheduler.advance(by: .seconds(seconds))
        }

        func reads() async -> Int { await reader.reads }
        func memoryReads() async -> Int { await memory.reads }
    }

    final class TestClock {
        var date = Date(timeIntervalSinceReferenceDate: 5_000)
    }

    @Test func aMacWhoseSMCCannotBeOpenedStillRunsWithTheMemoryAlone() async {
        let f = await Fixture(FakeThermalReader(available: false))
        #expect(f.harness.registry.state(of: "performance") == .running)
        #expect(f.module.state.hasThermal == false)
        f.appear()
        await settle { await f.memoryReads() == 1 }
        await settle { f.module.state.usage != nil }
        await settle { !f.module.isReading }
        #expect(f.module.state.usage == FakeMemoryReader.usage)
        #expect(await f.reads() == 0, "there are no sensors to read")
    }

    @Test func withoutSensorsNoTemperatureStripIsOffered() async {
        let f = await Fixture(FakeThermalReader(available: false), strip: true)
        #expect(f.module.state.stripTemperature == false)
        #expect(f.harness.activities.current == nil)
        #expect(f.harness.scheduler.pendingCount == 0)
    }

    @Test func runningButHiddenNothingIsScheduledOrRead() async {
        let f = await Fixture()
        #expect(f.harness.registry.state(of: "performance") == .running)
        #expect(f.harness.scheduler.pendingCount == 0)
        await f.advance(60)
        await idle()
        #expect(await f.reads() == 0, "starting checks the SMC can be opened and reads nothing")
        #expect(await f.memoryReads() == 0)
    }

    @Test func openingTheTabReadsAtOnceAndThenEveryTwoSeconds() async {
        let f = await Fixture()
        f.appear()
        await settle { await f.reads() == 1 }
        #expect(await f.reads() == 1)
        await settle { !f.module.isReading }
        #expect(f.module.state.thermal == FakeThermalReader.warm)
        await settle { !f.module.isReading }
        #expect(f.harness.scheduler.pendingCount == 1)

        await f.advance(2)
        await settle { await f.reads() == 2 }
        #expect(await f.reads() == 2)
        await f.advance(2)
        await settle { await f.reads() == 3 }
        #expect(await f.reads() == 3)
    }

    @Test func closingTheTabStopsReading() async {
        let f = await Fixture()
        f.appear()
        await settle { await f.reads() == 1 }
        f.disappear()
        #expect(f.harness.scheduler.pendingCount == 0)
        await f.advance(30)
        await idle()
        #expect(await f.reads() == 1)
        #expect(f.module.state.isTabVisible == false)
        #expect(f.module.state.thermal == nil, "nothing shows it now")
    }

    @Test func aSecondScreenKeepsItGoingUntilItsTabIsGoneToo() async {
        let f = await Fixture()
        f.appear()
        f.appear()
        await settle { await f.reads() == 1 }
        f.disappear()
        #expect(f.module.state.isTabVisible)
        await f.advance(2)
        await settle { await f.reads() == 2 }
        #expect(await f.reads() == 2)
        f.disappear()
        #expect(f.harness.scheduler.pendingCount == 0)
        #expect(f.module.state.isTabVisible == false)
    }

    @Test func aReadStillRunningWhenTheLastTabGoesDoesNotSchedulePollingAgain() async {
        let f = await Fixture()
        await f.reader.hold()
        f.appear()
        await settle { await f.reads() == 1 }
        f.disappear()
        await f.reader.release()
        await settle { !f.module.isReading }
        #expect(f.harness.scheduler.pendingCount == 0)
        await f.advance(10)
        await idle()
        #expect(await f.reads() == 1)
    }

    @Test func aTabThatComesBackDuringAReadDoesNotStartASecondRead() async {
        let f = await Fixture()
        await f.reader.hold()
        f.appear()
        await settle { await f.reads() == 1 }
        f.disappear()
        f.appear()
        await idle()
        #expect(await f.reads() == 1)
        await f.reader.release()
        await settle { f.harness.scheduler.pendingCount == 1 }
        await settle { !f.module.isReading }
        #expect(f.harness.scheduler.pendingCount == 1, "polling carries on")
        #expect(await f.reads() == 1)
    }

    @Test func eachReadAddsTheSoCToTheHistory() async {
        let f = await Fixture()
        f.appear()
        await settle { f.module.state.history.samples.count == 1 }
        await f.advance(2)
        await settle { f.module.state.history.samples.count == 2 }
        #expect(f.module.state.history.samples.map(\.value) == [78, 78])
        await f.reader.answer(with: ThermalSnapshot(cpu: 60, gpu: 82, fans: []))
        await f.advance(2)
        await settle { f.module.state.history.samples.count == 3 }
        #expect(f.module.state.history.samples.last?.value == 82)
        #expect(f.module.state.history.samples.last?.date == f.clock.date)
    }

    @Test func aReadThatFailsKeepsTheLastNumbersAndPollingCarriesOn() async {
        let f = await Fixture()
        f.appear()
        await settle { await f.reads() == 1 }
        await f.reader.answer(with: nil)
        await f.advance(2)
        await settle { await f.reads() == 2 }
        await settle { f.harness.scheduler.pendingCount == 1 }
        await settle { !f.module.isReading }
        #expect(f.module.state.thermal == FakeThermalReader.warm)
        #expect(f.module.state.history.samples.count == 1)
        await settle { !f.module.isReading }
        #expect(f.harness.scheduler.pendingCount == 1)
    }

    @Test func aReadWithNoDieTemperatureAddsNothingToTheHistory() async {
        let f = await Fixture(FakeThermalReader(ThermalSnapshot(cpu: nil, gpu: nil, fans: [])))
        f.appear()
        await settle { await f.reads() == 1 }
        await settle { !f.module.isReading }
        #expect(f.module.state.history.samples.isEmpty)
    }

    @Test func disablingTheModuleStopsEverythingAndLetsGoOfTheSMC() async {
        let f = await Fixture()
        f.appear()
        await settle { await f.reads() == 1 }
        await f.harness.registry.setEnabled(false, for: "performance")
        #expect(await f.reader.shutdowns == 1)
        #expect(f.harness.scheduler.pendingCount == 0)
        #expect(f.module.state.thermal == nil)
        #expect(f.module.state.history.samples.isEmpty)
        await f.advance(10)
        await idle()
        #expect(await f.reads() == 1)
    }

    @Test func startingAgainAfterBeingDisabledWorks() async {
        let f = await Fixture()
        await f.harness.registry.setEnabled(false, for: "performance")
        await f.harness.registry.setEnabled(true, for: "performance")
        #expect(f.harness.registry.state(of: "performance") == .running)
        f.appear()
        await settle { await f.reads() == 1 }
        await settle { !f.module.isReading }
        #expect(f.module.state.thermal == FakeThermalReader.warm)
    }

    // MARK: Strip

    @Test func theStripIsOffByDefaultAndNothingIsPublished() async {
        let f = await Fixture()
        #expect(f.harness.activities.current == nil)
        #expect(f.module.state.stripTemperature == false)
    }

    @Test func turningTheStripOnPublishesALowPriorityActivityAndStartsReading() async {
        let f = await Fixture()
        f.harness.settings.set(true, for: Self.stripKey)
        await settle { f.harness.activities.current != nil }
        let entry = f.harness.activities.current
        #expect(entry?.id == "performance/strip")
        #expect(entry?.activity.priority == .low)
        #expect(entry?.activity.summary == "Nhiệt độ SoC")
        await settle { await f.reads() == 1 }
        #expect(await f.reads() == 1)
        #expect(f.module.state.isTabVisible == false)
        await f.advance(2)
        await settle { await f.reads() == 2 }
        #expect(await f.reads() == 2)
    }

    @Test func theStripSetBeforeStartShowsAndReadsFromTheStart() async {
        let f = await Fixture(strip: true)
        #expect(f.harness.activities.current?.id == "performance/strip")
        await settle { await f.reads() == 1 }
        await settle { !f.module.isReading }
        #expect(f.module.state.thermal == FakeThermalReader.warm)
        await settle { !f.module.isReading }
        #expect(f.harness.scheduler.pendingCount == 1)
    }

    @Test func turningTheStripOffClearsItAndStopsReadingWhenNoTabIsOpen() async {
        let f = await Fixture(strip: true)
        await settle { await f.reads() == 1 }
        f.harness.settings.set(false, for: Self.stripKey)
        await settle { f.harness.activities.current == nil }
        #expect(f.harness.activities.current == nil)
        await settle { f.harness.scheduler.pendingCount == 0 }
        #expect(f.harness.scheduler.pendingCount == 0)
        await f.advance(10)
        await idle()
        #expect(await f.reads() == 1)
    }

    @Test func turningTheStripOffKeepsReadingWhileATabIsOpen() async {
        let f = await Fixture(strip: true)
        f.appear()
        await settle { await f.reads() == 1 }
        f.harness.settings.set(false, for: Self.stripKey)
        await settle { f.harness.activities.current == nil }
        await f.advance(2)
        await settle { await f.reads() == 2 }
        #expect(await f.reads() == 2)
        f.disappear()
        #expect(f.harness.scheduler.pendingCount == 0)
    }

    @Test func closingTheTabKeepsReadingWhileTheStripIsOn() async {
        let f = await Fixture(strip: true)
        f.appear()
        await settle { await f.reads() == 1 }
        f.disappear()
        await settle { !f.module.isReading }
        #expect(f.harness.scheduler.pendingCount == 1)
        await f.advance(2)
        await settle { await f.reads() == 2 }
        #expect(await f.reads() == 2)
    }

    @Test func theStripIsPublishedOnceNotAtEveryRead() async {
        let f = await Fixture(strip: true)
        await settle { await f.reads() == 1 }
        await settle { !f.module.isReading }
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = f.harness.activities.current } onChange: { changes += 1 }
        for expected in 2...4 {
            await f.advance(2)
            await settle { await f.reads() == expected }
            await settle { !f.module.isReading }
        }
        #expect(changes == 0, "the strip's views follow the state, so the notch is not asked to redraw")
    }

    @Test func theStripNeverTakesTheNotchFromMusic() async {
        let f = await Fixture(strip: true)
        let music = LiveActivity(id: "nowPlaying", priority: .normal, leading: AnyView(EmptyView()), trailing: AnyView(EmptyView()))
        f.harness.activities.set(music, from: "media")
        #expect(f.harness.activities.current?.id == "media/nowPlaying")
        #expect(f.harness.activities.others.map(\.id) == ["performance/strip"])
    }

    @Test func disablingTheModuleRemovesTheStrip() async {
        let f = await Fixture(strip: true)
        await f.harness.registry.setEnabled(false, for: "performance")
        #expect(f.harness.activities.current == nil)
    }

    // MARK: Tab and settings

    @Test func theTabIsNamedAndFitsWhatANotchAllows() async throws {
        let f = await Fixture()
        let tab = try #require(f.module.makeTab())
        #expect(tab.id == "performance")
        #expect(tab.title == "Hiệu năng")
        #expect(f.harness.oversizedTabs.reports.isEmpty)
        #expect(NotchTab.heightRange.contains(try #require(tab.preferredHeight)))
        #expect(f.harness.registry.tabs.map(\.id) == ["performance"])
    }

    @Test func theSymbolsAreSFSymbols() async throws {
        let f = await Fixture()
        let tab = try #require(f.module.makeTab())
        for name in [f.module.descriptor.systemImage, tab.systemImage, "thermometer.medium", "fan"] {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }

    @Test func settingsRowsExistBeforeTheModuleEverStarts() throws {
        let harness = RegistryHarness([PerformanceModule(thermal: FakeThermalReader(), memory: FakeMemoryReader(), now: { .now })])
        #expect(harness.registry.state(of: "performance") == .disabled)
        let view = try #require(harness.registry.settingsView(for: "performance"))
        #expect(String(describing: view).hasPrefix("AnyView(PerformanceSettingsView("))
    }

    @Test func theStripSettingIsOffUntilTheUserTurnsItOn() throws {
        let harness = RegistryHarness([PerformanceModule(thermal: FakeThermalReader(), memory: FakeMemoryReader(), now: { .now })])
        let environment = try #require(harness.settingsEnvironment(for: "performance"))
        let key = PerformanceSettingsKeys(environment.settings).stripTemperature
        #expect(key.name == "module.performance.stripTemperature")
        #expect(environment.settings.value(key) == false)
    }
}
