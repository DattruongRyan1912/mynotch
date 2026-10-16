import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import PortsModule

/// What the module did to the world besides signals: pages opened and lines copied. Never the real workspace or pasteboard.
@MainActor final class Outside {
    var opened: [URL] = []
    var copied: [String] = []
}

extension StopPolicy {
    static let test = StopPolicy(currentUID: 501, ownPID: 700, ownBundlePath: "/Applications/MyNotch.app")
}

/// A module wired to fakes only: the ports, the processes the signals reach, the probe and the outside world.
@MainActor struct Rig {
    let module: PortsModule
    let harness: RegistryHarness
    let source: FakePortSource
    let control: FakeProcessControl
    let probe: FakePortProbe
    let outside: Outside
    /// The notch's app-wide settings the module reads, its own to change from a test.
    let interface = NotchInterface()

    var state: PortsState { module.state }
    var scheduler: ManualScheduler { harness.scheduler }

    init(_ entries: [PortEntry] = [], policy: StopPolicy = .test, running: Bool = true, hiding: CaptureHiding = .never) async {
        interface.captureHiding = hiding
        source = FakePortSource(entries)
        control = FakeProcessControl(entries.map(\.process.identity))
        probe = FakePortProbe()
        let outside = Outside()
        self.outside = outside
        module = PortsModule(
            source: source, control: control, probe: probe, policy: policy,
            environment: PortsEnvironment(openURL: { outside.opened.append($0) }, copy: { outside.copied.append($0) }),
            interface: interface
        )
        harness = RegistryHarness([module])
        if running { await harness.registry.bootstrap() }
    }

    /// The tab on screen, with the first read done.
    func showTab() async {
        module.tabAppeared()
        await module.idle()
    }

    func advance(_ seconds: Double) async {
        scheduler.advance(by: .milliseconds(Int(seconds * 1000)))
        await module.idle()
    }
}

@Suite struct PortsModuleTests {
    let node = PortEntry.make(port: 3000, process: .make(pid: 10, name: "node", startTime: 1_000))
    let python = PortEntry.make(port: 8000, process: .make(pid: 11, name: "Python", command: "python3 -m http.server", startTime: 2_000))

    // MARK: The module

    @Test func itIsCalledCongAndStartsWithoutReadingAnything() async {
        let rig = await Rig([node])
        #expect(rig.module.descriptor.id == "ports")
        #expect(rig.module.descriptor.displayName == "Cổng")
        #expect(rig.module.descriptor.defaultEnabled)
        #expect(rig.harness.registry.state(of: "ports") == .running)
        #expect(rig.source.reads == 0, "nothing is read while no tab is on screen")
        #expect(rig.scheduler.pendingCount == 0, "and nothing is waiting to read")
    }

    @Test func itsTabTakesTheKeyboardAndIsNotTallerThanTheNotchAllows() async throws {
        let rig = await Rig([node])
        let tab = try #require(rig.harness.registry.tabs.first { $0.id == "ports" })
        #expect(tab.title == "Cổng")
        #expect(tab.acceptsKeyboard)
        #expect(tab.preferredHeight == PortsModule.tabHeight)
        #expect(!tab.asksTooMuch)
        #expect(rig.harness.oversizedTabs.reports.isEmpty)
    }

    // MARK: Polling

    @Test func openingTheTabReadsAtOnceAndThenEveryTwoSeconds() async {
        let rig = await Rig([node])
        await rig.showTab()
        #expect(rig.source.reads == 1)
        #expect(rig.state.entries == [node])
        #expect(rig.state.hasLoaded)

        await rig.advance(1.9)
        #expect(rig.source.reads == 1)
        await rig.advance(0.1)
        #expect(rig.source.reads == 2)
        await rig.advance(2)
        await rig.advance(2)
        #expect(rig.source.reads == 4)
    }

    @Test func aChangeOnTheMachineShowsOnTheNextRead() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.source.set([node, python])
        await rig.advance(2)
        #expect(rig.state.entries.map(\.port) == [3000, 8000])
        rig.source.set([python])
        await rig.advance(2)
        #expect(rig.state.entries.map(\.port) == [8000])
    }

    @Test func closingTheTabStopsAllReading() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.module.tabDisappeared()
        #expect(rig.scheduler.pendingCount == 0)
        await rig.advance(30)
        #expect(rig.source.reads == 1)
        #expect(!rig.state.isTabVisible)
    }

    @Test func aReadStillOnItsWayWhenTheTabClosesDoesNotStartTheTimerAgain() async {
        let rig = await Rig([node])
        rig.module.tabAppeared()
        rig.module.tabDisappeared()   // before the read has finished
        await rig.module.idle()
        #expect(rig.scheduler.pendingCount == 0)
        await rig.advance(30)
        #expect(rig.source.reads == 1)
    }

    @Test func twoScreensKeepItReadingUntilBothTabsAreHidden() async {
        let rig = await Rig([node])
        await rig.showTab()
        await rig.showTab()
        rig.module.tabDisappeared()
        #expect(rig.scheduler.pendingCount == 1, "one tab is still on screen")
        rig.module.tabDisappeared()
        #expect(rig.scheduler.pendingCount == 0)
    }

    @Test func aTabOpenedWhileAReadIsRunningDoesNotStartAnother() async {
        let rig = await Rig([node])
        rig.module.tabAppeared()
        rig.module.tabAppeared()
        await rig.module.idle()
        #expect(rig.source.reads == 1)
        #expect(rig.scheduler.pendingCount == 1, "one timer, not two")
    }

    @Test func reopeningTheTabReadsAgainAtOnce() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.module.tabDisappeared()
        rig.source.set([python])
        await rig.showTab()
        #expect(rig.source.reads == 2)
        #expect(rig.state.entries == [python])
    }

    @Test func switchingTheModuleOffCancelsTheTimerAndDropsALateAnswer() async {
        let rig = await Rig([node])
        rig.module.tabAppeared()   // the read is on its way
        await rig.harness.registry.setEnabled(false, for: "ports")
        await rig.module.idle()
        #expect(rig.state.entries.isEmpty, "the answer of a module that stopped is not shown")
        #expect(rig.scheduler.pendingCount == 0)
        #expect(!rig.state.hasLoaded)
        await rig.advance(10)
        #expect(rig.source.reads == 1)
    }

    @Test func aTabThatAppearsBeforeTheModuleRunsReadsNothing() async {
        let rig = await Rig([node], running: false)
        rig.module.tabAppeared()
        await rig.module.idle()
        #expect(rig.source.reads == 0)
    }

    // MARK: Actions

    @Test func openGoesToLocalhostForTCPOnly() async {
        let udp = PortEntry.make(port: 5353, proto: .udp, process: .make(pid: 12))
        let rig = await Rig([node, udp])
        rig.module.open(node)
        rig.module.open(udp)
        #expect(rig.outside.opened == [URL(string: "http://localhost:3000")])
    }

    @Test func copyPutsLocalhostAndThePortOnTheClipboard() async {
        let rig = await Rig([node])
        rig.module.copy(node)
        #expect(rig.outside.copied == ["localhost:3000"])
    }

    // MARK: Quick check

    @Test func aHeldPortIsAnsweredFromTheListWithoutAskingTheSystem() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.state.quickQuery = "3000"
        rig.module.quickQueryChanged()
        await rig.module.idle()
        #expect(rig.probe.asked.isEmpty)
        #expect(rig.state.quickAnswer.message == "Cổng 3000: node · PID 10")
    }

    @Test func aFreePortIsAskedAboutAndOnlyThenCalledFree() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.state.quickQuery = "4000"
        #expect(rig.state.quickAnswer == .checking(4000), "not free before the system said so")
        rig.module.quickQueryChanged()
        await rig.module.idle()
        #expect(rig.probe.asked == [4000])
        #expect(rig.state.quickAnswer.message == "Cổng 4000 trống")
    }

    @Test func aPortHeldBySomeoneWeCannotSeeIsNotCalledFree() async {
        let rig = await Rig([node])
        rig.probe.set(.inUse, for: 5432)
        await rig.showTab()
        rig.state.quickQuery = "5432"
        rig.module.quickQueryChanged()
        await rig.module.idle()
        #expect(rig.state.quickAnswer == .busyUnseen(5432))
    }

    @Test func theAnswerForAnEarlierKeystrokeIsDropped() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.state.quickQuery = "400"
        rig.module.quickQueryChanged()
        rig.state.quickQuery = "4000"
        rig.module.quickQueryChanged()
        await rig.module.idle()
        #expect(rig.state.probe == PortProbeOutcome(port: 4000, result: .free))
    }

    @Test func clearingTheFieldForgetsTheAnswer() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.state.quickQuery = "4000"
        rig.module.quickQueryChanged()
        await rig.module.idle()
        rig.state.quickQuery = ""
        rig.module.quickQueryChanged()
        #expect(rig.state.probe == nil)
        #expect(rig.state.quickAnswer == .empty)
    }

    @Test func aPortThatBecomesFreeWhileItsOwnerIsShownIsAskedAboutOnTheNextRead() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.state.quickQuery = "3000"
        rig.module.quickQueryChanged()
        #expect(rig.probe.asked.isEmpty)
        rig.source.set([])
        await rig.advance(2)
        #expect(rig.probe.asked == [3000])
        #expect(rig.state.quickAnswer == .free(3000))
    }

    // MARK: Command lines and screen capture

    let withCommand = PortEntry.make(port: 3000, process: .make(pid: 10, name: "node", command: "node server.js --watch"))

    @Test func theCommandLineIsShownWhileMyNotchIsNotKeptOutOfRecordings() async {
        let rig = await Rig([withCommand])
        await rig.showTab()
        #expect(rig.state.showsCommandLines)
        #expect(PortRow.commandLine(of: withCommand, shown: rig.state.showsCommandLines) == "node server.js --watch")
        #expect(rig.state.visibleEntries.count == 1)
    }

    @Test func onlyTheNeverSettingShowsTheCommandLine() {
        #expect(PortsModule.showsCommandLines(under: .never))
        #expect(!PortsModule.showsCommandLines(under: .whenCollapsed))
        #expect(!PortsModule.showsCommandLines(under: .always))
        for hiding in CaptureHiding.allCases {
            #expect(PortsModule.showsCommandLines(under: hiding) == (hiding == .never))
        }
    }

    @Test func whenTheSettingKeepsMyNotchOutOfRecordingsARowIsTheNameAlone() async {
        for hiding in [CaptureHiding.always, .whenCollapsed] {
            let rig = await Rig([withCommand], hiding: hiding)
            await rig.showTab()
            #expect(!rig.state.showsCommandLines, "\(hiding)")
            #expect(PortRow.commandLine(of: withCommand, shown: rig.state.showsCommandLines) == nil)
            #expect(rig.state.entries == [withCommand], "the name, port and owner are still there")
        }
    }

    @Test func theSettingChangingWhileTheModuleRunsChangesTheRowsAtOnce() async {
        let rig = await Rig([withCommand])
        await rig.showTab()
        rig.interface.captureHiding = .always
        for _ in 0..<100 where rig.state.showsCommandLines { await Task.yield() }
        #expect(!rig.state.showsCommandLines)
        rig.interface.captureHiding = .never
        for _ in 0..<100 where !rig.state.showsCommandLines { await Task.yield() }
        #expect(rig.state.showsCommandLines)
    }

    @Test func aCommandLineThatIsNotShownIsNotSearchedEither() async {
        let rig = await Rig([withCommand])
        await rig.showTab()
        rig.state.filter = "server.js"
        #expect(rig.state.visibleEntries.count == 1, "found by what it was started with")
        rig.interface.captureHiding = .always
        for _ in 0..<100 where rig.state.showsCommandLines { await Task.yield() }
        #expect(rig.state.visibleEntries.isEmpty, "a guess must not tell what the hidden line says")
        rig.state.filter = "node"
        #expect(rig.state.visibleEntries.count == 1, "the name still finds it")
        #expect(PortFilter.matches(withCommand, query: "server.js", searchesCommands: false) == false)
    }

    @Test func aStoppedModuleGoesBackToTheDefault() async {
        let rig = await Rig([withCommand], hiding: .always)
        #expect(!rig.state.showsCommandLines)
        await rig.harness.registry.setEnabled(false, for: "ports")
        #expect(rig.state.showsCommandLines)
    }

    // MARK: Settings

    @Test func udpIsHiddenUntilTheSettingAsksForIt() async throws {
        let udp = PortEntry.make(port: 5353, proto: .udp, process: .make(pid: 12, name: "Chrome"))
        let rig = await Rig([node, udp])
        await rig.showTab()
        #expect(!rig.state.showUDP)
        #expect(rig.state.visibleEntries.map(\.port) == [3000])

        let environment = try #require(rig.harness.settingsEnvironment(for: "ports"))
        environment.settings.binding(PortsModule.showUDPKey(environment.settings)).wrappedValue = true
        for _ in 0..<100 where !rig.state.showUDP { await Task.yield() }
        #expect(rig.state.visibleEntries.map(\.port) == [3000, 5353])
    }

    @Test func theSettingRowExistsBeforeTheModuleEverStarts() async throws {
        let rig = await Rig([node], running: false)
        #expect(rig.harness.registry.state(of: "ports") == .disabled)
        let view = try #require(rig.harness.registry.settingsView(for: "ports"))
        #expect(String(describing: view).hasPrefix("AnyView(PortsSettingsView("))
    }

    @Test func aSettingMadeBeforeTheFirstStartAppliesWhenItStarts() async throws {
        let rig = await Rig([node], running: false)
        let environment = try #require(rig.harness.settingsEnvironment(for: "ports"))
        environment.settings.binding(PortsModule.showUDPKey(environment.settings)).wrappedValue = true
        await rig.harness.registry.bootstrap()
        #expect(rig.state.showUDP)
    }

    @Test func switchingOffClearsWhatWasShown() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.state.filter = "node"
        await rig.harness.registry.setEnabled(false, for: "ports")
        #expect(rig.state.entries.isEmpty)
        #expect(rig.state.filter.isEmpty)
        #expect(rig.state.flows.isEmpty)
    }
}
