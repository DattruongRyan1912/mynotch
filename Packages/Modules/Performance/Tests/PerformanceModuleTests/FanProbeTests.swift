import Foundation
import Synchronization
import Testing
@testable import PerformanceModule

/// A fan as the helper presents it, with just enough physics for the probe: the speed moves part of the way to where it is told to
/// go each time it is read, up or down. How it answers each way of setting it is up to the test. Nothing here is a real SMC.
nonisolated final class SimulatedFanClient: FanHelperClient, Sendable {
    struct Behaviour {
        var floorWorks = true
        /// The target stays at what was written after the fan is given back, as if the firmware never took it back.
        var floorSticky = false
        var forcedWorks = true
        var forcedRefused = false
        var forcedSticky = false
        var failReading = false
        /// The firmware reports its own target instead of the one written while a floor is held, as if it were rewriting it.
        var floorTargetNotKept = false
        /// The first this many readings fail (a helper that is still starting), and the first this many that do not fail are empty.
        var failFirstReads = 0
        var emptyFirstReads = 0
        /// The answer leaves out the fan being probed.
        var omitFan0 = false
        /// How long the helper says the first manual command's modes took to read back; nothing for the ones after it.
        var modeReadBackMS: Int?
    }

    private struct State {
        var rpm: Double
        let apple: Double
        let maximum: Double
        var mode = 0.0
        var target: Double
        var floorActive = false
        var reads = 0
        var behaviour: Behaviour
        var commands: [FakeFanHelperClient.Command] = []
        var errorOnCommand: Int?
        var forcedCommands = 0
    }

    private let state: Mutex<State>

    init(apple: Double = 2100, maximum: Double = 5779, behaviour: Behaviour = Behaviour()) {
        state = Mutex(State(rpm: apple, apple: apple, maximum: maximum, target: apple, behaviour: behaviour))
    }

    var commands: [FakeFanHelperClient.Command] { state.withLock { $0.commands } }
    func failCommand(number: Int) { state.withLock { $0.errorOnCommand = number } }

    func ping() async throws -> FanHelperInfo { .matching }

    func readFans() async throws -> [FanHelperFanInfo] {
        try state.withLock { state in
            state.reads += 1
            if state.behaviour.failReading || state.reads <= state.behaviour.failFirstReads { throw FanHelperError.timeout }
            if state.reads <= state.behaviour.failFirstReads + state.behaviour.emptyFirstReads { return [] }
            let heldAt = state.mode == 1 || state.floorActive ? state.target : state.apple
            state.rpm += 0.6 * (heldAt - state.rpm)
            let reported = state.floorActive && state.behaviour.floorTargetNotKept ? state.apple : state.target
            let first = FanHelperFanInfo(index: 0, rpm: state.rpm, minRPM: 1200, maxRPM: state.maximum, mode: state.mode, target: reported)
            let second = FanHelperFanInfo(index: 1, rpm: state.apple, minRPM: 1200, maxRPM: state.maximum, mode: 0, target: state.apple)
            return state.behaviour.omitFan0 ? [second] : [first, second]
        }
    }

    func setFloor(fan: Int, rpm: Double) async throws -> FanCommandResult {
        try command(.floor(fan, rpm)) { state in
            state.target = rpm
            state.floorActive = state.behaviour.floorWorks
            return FanCommandResult(ok: true, state: .floor, appliedRPM: rpm, leaseSeconds: 15)
        }
    }

    func setForced(fan: Int, rpm: Double) async throws -> FanCommandResult {
        try command(.forced(fan, rpm)) { state in
            if state.behaviour.forcedRefused { return FanCommandResult(ok: false, state: .automatic, detail: "the SMC refused F0Md (0x82)") }
            state.forcedCommands += 1
            state.mode = state.behaviour.forcedWorks ? 1 : 0
            state.target = rpm
            return FanCommandResult(
                ok: true, state: .forced, appliedRPM: rpm, leaseSeconds: 15,
                modeReadBackMS: state.forcedCommands == 1 ? state.behaviour.modeReadBackMS : nil
            )
        }
    }

    func setAuto(fan: Int) async throws -> FanCommandResult {
        try command(.auto(fan)) { state in
            let wasForced = state.mode == 1
            state.mode = 0
            if state.floorActive {
                if !state.behaviour.floorSticky {
                    state.floorActive = false
                    state.target = state.apple
                }
            } else if wasForced {
                if !state.behaviour.forcedSticky { state.target = state.apple }
            } else {
                state.target = state.apple
            }
            return FanCommandResult(ok: true, state: .automatic)
        }
    }

    private func command(_ command: FakeFanHelperClient.Command, _ body: (inout State) -> FanCommandResult) throws -> FanCommandResult {
        try state.withLock { state in
            state.commands.append(command)
            if state.errorOnCommand == state.commands.count { throw FanHelperError.timeout }
            return body(&state)
        }
    }
}

/// A client that notices if two calls to the helper are ever in flight at once.
nonisolated final class OverlapWatchingClient: FanHelperClient, Sendable {
    private let base: SimulatedFanClient
    private let counts = Mutex((inFlight: 0, mostInFlight: 0, calls: 0))

    init(_ base: SimulatedFanClient) { self.base = base }

    var mostInFlight: Int { counts.withLock { $0.mostInFlight } }
    var calls: Int { counts.withLock { $0.calls } }

    private func watched<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        counts.withLock {
            $0.inFlight += 1
            $0.calls += 1
            $0.mostInFlight = max($0.mostInFlight, $0.inFlight)
        }
        defer { counts.withLock { $0.inFlight -= 1 } }
        await Task.yield()
        return try await body()
    }

    func ping() async throws -> FanHelperInfo { try await watched { try await base.ping() } }
    func readFans() async throws -> [FanHelperFanInfo] { try await watched { try await base.readFans() } }
    func setFloor(fan: Int, rpm: Double) async throws -> FanCommandResult { try await watched { try await base.setFloor(fan: fan, rpm: rpm) } }
    func setForced(fan: Int, rpm: Double) async throws -> FanCommandResult { try await watched { try await base.setForced(fan: fan, rpm: rpm) } }
    func setAuto(fan: Int) async throws -> FanCommandResult { try await watched { try await base.setAuto(fan: fan) } }
}

@Suite struct FanProbeTests {
    /// The pauses a probe asked for, instead of waiting them.
    @MainActor final class Pauses {
        var durations: [Duration] = []
    }

    @MainActor final class Lines {
        var all: [String] = []
    }

    @MainActor func probe(_ client: SimulatedFanClient, _ pauses: Pauses = Pauses(), _ lines: Lines = Lines()) -> FanControlProbe {
        FanControlProbe(
            client: client, pause: { pauses.durations.append($0) }, now: { Date(timeIntervalSinceReferenceDate: 7) },
            log: { lines.all.append($0) }
        )
    }

    // MARK: The rules

    @Test func theRequestIs1500AboveTheBaselineOr60PercentOfTheMaximumWhicheverIsMore() {
        #expect(FanProbeJudge.requestedRPM(baseline: 2100, maximum: 5779) == 3600, "1500 above 2100 beats 60 % of 5779 (3467)")
        #expect(FanProbeJudge.requestedRPM(baseline: 1200, maximum: 5779).map { abs($0 - 3467.4) < 0.1 } == true, "60 % of the maximum beats 1500 above 1200")
    }

    @Test func theRequestNeverPassesTheMaximum() {
        #expect(FanProbeJudge.requestedRPM(baseline: 4500, maximum: 6000) == 6000)
    }

    @Test func aFanTooNearItsMaximumToShowAChangeIsNotJudged() {
        #expect(FanProbeJudge.requestedRPM(baseline: 5300, maximum: 5779) == nil)
        #expect(FanProbeJudge.requestedRPM(baseline: 5000, maximum: 5779) == nil, "779 rpm of room is under the 800 it needs")
        #expect(FanProbeJudge.requestedRPM(baseline: 4979, maximum: 5779) == 5779, "exactly 800 of room is enough")
    }

    @Test func aFanChangedWhenItWentMostOfTheWayToTheRequest() {
        #expect(FanProbeJudge.changed(baseline: 2000, requested: 3500, peak: 2600))
        #expect(FanProbeJudge.changed(baseline: 2000, requested: 3500, peak: 2599) == false)
        #expect(FanProbeJudge.changed(baseline: 2000, requested: 3500, peak: 2000) == false)
    }

    @Test func aFanIsGivenBackWhenTheModeIsAutomaticAndTheTargetOrTheSpeedGoesBack() {
        func restored(mode: Double? = 0, target: Double? = 3500, rpm: Double? = 3500) -> Bool {
            FanProbeJudge.restored(modeAfter: mode, targetAfter: target, rpmAfter: rpm, requested: 3500, peak: 3400, baseline: 2000)
        }
        #expect(restored(target: 2100), "the firmware took the target back")
        #expect(restored(target: 3500, rpm: 2900), "the speed is on its way down")
        #expect(restored(target: 3500, rpm: 3400) == false, "nothing came back")
        #expect(restored(mode: 1, target: 2100, rpm: 2000) == false, "still manual")
        #expect(restored(mode: nil, target: 2100, rpm: 2000) == false, "nothing could be read")
    }

    @Test func theFloorIsPreferredWhenBothPassAndNeitherPassingIsNone() {
        func trial(_ mechanism: FanMechanism, usable: Bool) -> MechanismTrial {
            MechanismTrial(
                mechanism: mechanism, accepted: true, detail: "", baselineRPM: 2000, requestedRPM: 3500, peakRPM: usable ? 3400 : 2000,
                changed: usable, heldAsAsked: true, modeAfter: 0, targetAfter: 2000, rpmAfter: 2000, restored: true
            )
        }
        #expect(FanProbeJudge.verdict(for: [trial(.floor, usable: true), trial(.forced, usable: true)]) == .floor)
        #expect(FanProbeJudge.verdict(for: [trial(.floor, usable: false), trial(.forced, usable: true)]) == .forced)
        #expect(FanProbeJudge.verdict(for: [trial(.floor, usable: false), trial(.forced, usable: false)]) == .none)
    }

    @Test func aWayThatDidNotRestoreIsNotUsableEvenIfItChangedTheSpeed() {
        let trial = MechanismTrial(
            mechanism: .floor, accepted: true, detail: "", baselineRPM: 2000, requestedRPM: 3500, peakRPM: 3400, changed: true, heldAsAsked: true,
            modeAfter: 0, targetAfter: 3500, rpmAfter: 3400, restored: false
        )
        #expect(trial.usable == false)
    }

    @Test func theTwoTrialsTakeTenSecondsAsTheButtonSays() {
        #expect(2 * (FanControlProbe.holdSeconds + FanControlProbe.settleSeconds) == 10)
        #expect(FanProbePresentation.buttonTitle == "Thử điều khiển quạt (10 giây)")
    }

    // MARK: The sequence

    @MainActor @Test func whenBothWaysWorkItReadsTheBaselineTriesTheFloorThenTheManualSpeedAndGivesTheFanBackAfterEach() async {
        let client = SimulatedFanClient()
        let pauses = Pauses()
        let outcome = await probe(client, pauses).run()
        #expect(outcome.verdict == .floor && outcome.mechanism == .floor)
        #expect(outcome.trials.map(\.mechanism) == [.floor, .forced] && outcome.trials.allSatisfy(\.usable))
        #expect(client.commands == [
            .floor(0, 3600), .floor(0, 3600), .floor(0, 3600), .auto(0), .auto(-1),
            .forced(-1, 3600), .forced(-1, 3600), .forced(-1, 3600), .auto(-1), .auto(-1),
            .auto(-1),
        ])
        #expect(pauses.durations == [.seconds(1), .seconds(1), .seconds(1), .seconds(2), .seconds(1), .seconds(1), .seconds(1), .seconds(2)])
        #expect(outcome.at == Date(timeIntervalSinceReferenceDate: 7))
    }

    @MainActor @Test func theLastThingItDoesIsToGiveEveryFanBack() async {
        for behaviour in [SimulatedFanClient.Behaviour(), .init(floorWorks: false, forcedRefused: true)] {
            let client = SimulatedFanClient(behaviour: behaviour)
            _ = await probe(client).run()
            #expect(client.commands.last == .auto(-1))
        }
    }

    @MainActor @Test func aFloorTheFirmwareIgnoresLeavesTheManualSpeedAsTheWay() async {
        let client = SimulatedFanClient(behaviour: .init(floorWorks: false))
        let outcome = await probe(client).run()
        #expect(outcome.verdict == .forced && outcome.mechanism == .forced)
        let floor = outcome.trials[0]
        #expect(floor.accepted && floor.changed == false && floor.usable == false)
    }

    @MainActor @Test func aFloorThatStaysAfterTheFanIsGivenBackIsNeverChosen() async {
        let client = SimulatedFanClient(behaviour: .init(floorWorks: true, floorSticky: true))
        let outcome = await probe(client).run()
        let floor = outcome.trials[0]
        #expect(floor.changed && floor.restored == false)
        #expect(outcome.mechanism != .floor, "it changed the speed but was not given back cleanly")
        #expect(outcome.verdict == .none, "and a floor that stays spoils what is measured after it, so the probe does not guess")
    }

    @MainActor @Test func aFloorWhoseTargetTheFirmwareRewritesIsNotHonouredAndIsNeverChosen() async {
        let client = SimulatedFanClient(behaviour: .init(floorTargetNotKept: true))
        let outcome = await probe(client).run()
        let floor = outcome.trials[0]
        #expect(floor.changed && floor.heldAsAsked == false && floor.usable == false)
        #expect(outcome.verdict == .forced, "the speed rose, but the firmware did not keep what was written: it is fighting the request")
    }

    @MainActor @Test func aFloorThatTheFirmwareKeepsWhileHeldAndTakesBackAfterTheModeWriteIsTheOneConsistentFloor() async {
        let outcome = await probe(SimulatedFanClient()).run()
        let floor = outcome.trials[0]
        #expect(floor.heldAsAsked && floor.changed && floor.restored && floor.usable)
        #expect(outcome.verdict == .floor)
    }

    @MainActor @Test func aManualSpeedThatDoesNotReadBackAsManualIsNotHeldAsAsked() {
        let manual = FanHelperFanInfo(index: 0, rpm: 3000, minRPM: 1200, maxRPM: 5779, mode: 1, target: 3600)
        let automatic = FanHelperFanInfo(index: 0, rpm: 3000, minRPM: 1200, maxRPM: 5779, mode: 0, target: 3600)
        let moved = FanHelperFanInfo(index: 0, rpm: 3000, minRPM: 1200, maxRPM: 5779, mode: 1, target: 3300)
        #expect(FanControlProbe.holds(manual, mechanism: .forced, requested: 3600))
        #expect(FanControlProbe.holds(automatic, mechanism: .forced, requested: 3600) == false)
        #expect(FanControlProbe.holds(automatic, mechanism: .floor, requested: 3600), "a floor is held with the mode automatic")
        #expect(FanControlProbe.holds(moved, mechanism: .floor, requested: 3600) == false, "300 away is not what was written")
        #expect(FanControlProbe.holds(FanHelperFanInfo(index: 0, rpm: 0, minRPM: 0, maxRPM: 0, mode: 1, target: 3550), mechanism: .forced, requested: 3600))
    }

    @MainActor @Test func theManualSpeedIsAskedOfEveryFanAtOnceAndEveryFanIsGivenBackWhileTheFloorStaysOnTheProbedFan() async {
        let client = SimulatedFanClient()
        _ = await probe(client).run()
        let commands = client.commands
        #expect(commands.filter { if case .floor = $0 { true } else { false } }.allSatisfy { $0 == .floor(0, 3600) })
        #expect(commands.filter { if case .forced = $0 { true } else { false } } == Array(repeating: .forced(FanCommandResult.allFans, 3600), count: 3))
        #expect(FanCommandResult.allFans == -1)
        let forcedStart = commands.firstIndex(of: .forced(-1, 3600)) ?? 0
        #expect(commands[(forcedStart + 3)...].first == .auto(-1), "after the manual speed, every fan, not only fan 0")
    }

    @MainActor @Test func howLongTheSMCTookToTakeTheModeIsInTheTrialAndOnTheScreen() async {
        let client = SimulatedFanClient(behaviour: .init(modeReadBackMS: 150))
        let outcome = await probe(client).run()
        let forced = outcome.trials[1]
        #expect(forced.accepted && forced.usable && forced.detail == "chế độ nhận sau 150 ms")
        #expect(outcome.trials[0].detail.isEmpty, "the floor writes no mode")
        let lines = FanProbePresentation.lines(outcome)
        #expect(lines[1].hasSuffix("trả về tự động: được; chế độ nhận sau 150 ms."), "\(lines[1])")
        #expect(lines[0].hasSuffix("trả về tự động: được."), "nothing to say about the floor")
    }

    @MainActor @Test func aHelperThatSaysNothingAboutTheModesLeavesTheTrialWithoutANote() async {
        let outcome = await probe(SimulatedFanClient()).run()
        #expect(outcome.trials[1].detail.isEmpty)
    }

    @MainActor @Test func aManualSpeedWhoseModeNeverTakesIsNotUsableAndTheVerdictIsNone() async {
        let client = SimulatedFanClient(behaviour: .init(floorWorks: false, forcedWorks: false))
        let outcome = await probe(client).run()
        #expect(outcome.trials[1].accepted && outcome.trials[1].heldAsAsked == false && outcome.trials[1].usable == false)
        #expect(outcome.verdict == .none)
    }

    @MainActor @Test func aManualSpeedThatTheFanFollowsAfterTheEveryFanCommandIsTheWayWhenTheFloorIsIgnored() async {
        let client = SimulatedFanClient(behaviour: .init(floorWorks: false, modeReadBackMS: 100))
        let outcome = await probe(client).run()
        #expect(outcome.verdict == .forced && outcome.mechanism == .forced)
        #expect(outcome.trials[1].changed && outcome.trials[1].heldAsAsked && outcome.trials[1].restored)
    }

    @MainActor @Test func aManualSpeedTheHelperRefusesIsReportedWithItsReasonAndTheFloorStillWins() async {
        let client = SimulatedFanClient(behaviour: .init(forcedRefused: true))
        let outcome = await probe(client).run()
        let forced = outcome.trials[1]
        #expect(forced.accepted == false && forced.detail == "the SMC refused F0Md (0x82)")
        #expect(outcome.verdict == .floor)
    }

    @MainActor @Test func whenNeitherWayWorksTheVerdictIsNone() async {
        let client = SimulatedFanClient(behaviour: .init(floorWorks: false, forcedWorks: false))
        let outcome = await probe(client).run()
        #expect(outcome.verdict == .none && outcome.mechanism == nil)
    }

    @MainActor @Test func aFanNearItsMaximumIsNotJudgedAndNothingIsSet() async {
        let client = SimulatedFanClient(apple: 5400, maximum: 5779)
        let outcome = await probe(client).run()
        #expect(outcome.verdict == .inconclusive && outcome.mechanism == nil)
        #expect(outcome.note.contains("nguội"))
        #expect(client.commands == [.auto(-1)], "only the final give-back")
    }

    @MainActor @Test func aHelperThatCannotReadTheFansIsInconclusiveAndNothingIsSet() async {
        let client = SimulatedFanClient(behaviour: .init(failReading: true))
        let outcome = await probe(client).run()
        #expect(outcome.verdict == .inconclusive)
        #expect(client.commands == [.auto(-1)])
    }

    @MainActor @Test func aCommandThatFailsMidwayIsAnUnacceptedTrialAndTheProbeCarriesOnAndGivesTheFanBack() async {
        let client = SimulatedFanClient()
        client.failCommand(number: 2)
        let outcome = await probe(client).run()
        #expect(outcome.trials[0].accepted == false)
        #expect(outcome.trials.count == 2)
        #expect(client.commands.last == .auto(-1))
    }

    @MainActor @Test func cancellingStopsBetweenTrialsAndStillGivesTheFanBack() async {
        let client = SimulatedFanClient()
        let task = Task { @MainActor in
            await FanControlProbe(client: client, pause: { _ in withUnsafeCurrentTask { $0?.cancel() } }).run()
        }
        let outcome = await task.value
        #expect(outcome.verdict == .inconclusive)
        #expect(outcome.note == "Đã dừng giữa chừng.")
        #expect(client.commands.last == .auto(-1))
    }

    @MainActor @Test func itTellsWhatItIsDoingAsItGoes() async {
        let client = SimulatedFanClient()
        nonisolated(unsafe) var steps: [String] = []
        _ = await probe(client).run { steps.append($0) }
        #expect(steps == ["Đọc tốc độ quạt hiện tại", "Thử đặt sàn tốc độ", "Thử đặt tốc độ thủ công"])
    }

    // MARK: The baseline (a helper that was not running answers late, or not at all)

    @MainActor @Test func aBaselineThatFailsOnceIsReadAgainAfterASecondAndTheProbeCarriesOn() async {
        let client = SimulatedFanClient(behaviour: .init(failFirstReads: 1))
        let pauses = Pauses()
        let lines = Lines()
        let outcome = await probe(client, pauses, lines).run()
        #expect(outcome.verdict == .floor, "the second look found the fan and the probe ran")
        #expect(pauses.durations.first == .seconds(1) && pauses.durations.count == 9, "one second to wait, then the eight pauses of the two trials")
        #expect(lines.all == ["probe baseline: readFans failed (helper không trả lời); trying again"])
    }

    @MainActor @Test func aBaselineThatFailsTwiceIsInconclusiveWithTheReasonAndNothingIsSet() async {
        let client = SimulatedFanClient(behaviour: .init(failReading: true))
        let pauses = Pauses()
        let lines = Lines()
        let outcome = await probe(client, pauses, lines).run()
        #expect(outcome.verdict == .inconclusive && outcome.mechanism == nil)
        #expect(outcome.note == "Helper không đọc được quạt: helper không trả lời.")
        #expect(client.commands == [.auto(-1)])
        #expect(pauses.durations == [.seconds(1)], "it waited once, between the two looks")
        #expect(lines.all == [
            "probe baseline: readFans failed (helper không trả lời); trying again",
            "probe baseline: readFans failed (helper không trả lời)",
        ])
    }

    @MainActor @Test func anAnswerWithNoFansIsReadAgainAndThenSaidSoWithItsOwnReason() async {
        let client = SimulatedFanClient(behaviour: .init(emptyFirstReads: 5))
        let lines = Lines()
        let outcome = await probe(client, Pauses(), lines).run()
        #expect(outcome.verdict == .inconclusive && outcome.note == "Helper không thấy quạt nào.")
        #expect(lines.all == ["probe baseline: readFans returned no fans; trying again", "probe baseline: readFans returned no fans"])
        #expect(client.commands == [.auto(-1)])
    }

    @MainActor @Test func anAnswerWithNoFansOnceAndFansTheNextTimeCarriesOn() async {
        let client = SimulatedFanClient(behaviour: .init(emptyFirstReads: 1))
        let outcome = await probe(client).run()
        #expect(outcome.verdict == .floor)
    }

    @MainActor @Test func anAnswerThatLeavesOutTheProbedFanIsSaidSoAndStillReadAgain() async {
        let client = SimulatedFanClient(behaviour: .init(omitFan0: true))
        let pauses = Pauses()
        let lines = Lines()
        let outcome = await probe(client, pauses, lines).run()
        #expect(outcome.verdict == .inconclusive && outcome.note == "Helper không có quạt được thử.")
        #expect(lines.all == [
            "probe baseline: readFans has no fan with the probed index; trying again", "probe baseline: readFans has no fan with the probed index",
        ])
        #expect(pauses.durations == [.seconds(1)])
        #expect(client.commands == [.auto(-1)])
    }

    @MainActor @Test func aFailureThatIsNotATimeoutIsDescribedByItsOwnReason() async {
        let client = SimulatedFanClient(behaviour: .init(failReading: true))
        let result = FanControlProbe.BaselineFailure.threw(FanHelperManager.describe(NSError(domain: NSCocoaErrorDomain, code: 4099)))
        #expect(result.note == "Helper không đọc được quạt: không có helper nào trả lời.")
        #expect(result.logLine == "probe baseline: readFans failed (không có helper nào trả lời)")
        _ = client
    }

    @MainActor @Test func theLogLinesCarryTheReasonAndNoMeasuredValue() async {
        for behaviour in [
            SimulatedFanClient.Behaviour(failReading: true), .init(emptyFirstReads: 9), .init(omitFan0: true),
        ] {
            let lines = Lines()
            _ = await probe(SimulatedFanClient(behaviour: behaviour), Pauses(), lines).run()
            #expect(lines.all.count == 2)
            #expect(lines.all.allSatisfy { line in !line.contains { $0.isNumber } }, "no number in \(lines.all)")
        }
    }

    /// In the helper's log the baseline read and the give-back arrived at the same instant. The probe never has two calls in flight:
    /// that happens when a call has given up and the next one starts while the helper is still on its way up.
    @MainActor @Test func theProbeNeverHasTwoCallsToTheHelperInFlightAtOnce() async {
        for behaviour in [SimulatedFanClient.Behaviour(), .init(failFirstReads: 1), .init(failReading: true)] {
            let watcher = OverlapWatchingClient(SimulatedFanClient(behaviour: behaviour))
            _ = await FanControlProbe(client: watcher, pause: { _ in }, now: { Date() }).run()
            #expect(watcher.mostInFlight == 1)
            #expect(watcher.calls > 0)
        }
    }

    @MainActor @Test func theProbedFanIsTheFirstFanAndTheHelperNumbersFromZero() async {
        let client = SimulatedFanClient()
        _ = await probe(client).run()
        #expect(client.commands.first == .floor(0, 3600))
        #expect(FanControlProbe(client: client).fan == 0)
    }

    @MainActor @Test func aProbeThatFindsItsBaselineLogsNothing() async {
        let lines = Lines()
        _ = await probe(SimulatedFanClient(), Pauses(), lines).run()
        #expect(lines.all.isEmpty)
    }

    /// The probe is the first call to a helper that has been idle-exited, so it starts the helper: launchd takes its time and the
    /// helper half a second more before it listens. The helper's log showed it serving a request after the app had given up at 3 s.
    @Test func aCallToAHelperThatHasToBeStartedMayWaitLongerThanAColdStartTakes() {
        #expect(XPCFanHelperClient.timeout >= .seconds(10))
    }

    // MARK: Words

    @Test func theConfirmationSaysWhatWillHappenInNumbers() {
        let text = FanProbePresentation.confirmationMessage
        for part in ["10 giây", "hai lần", "5 giây", "1500 vòng/phút", "60%", "ồn hơn", "tự động của Apple", "95 °C", "Macs Fan Control", "quyền root"] {
            #expect(text.contains(part), "\(part)")
        }
    }

    @Test func eachVerdictHasItsSentence() {
        func say(_ verdict: FanProbeOutcome.Verdict, note: String = "") -> String {
            FanProbePresentation.verdict(FanProbeOutcome(verdict: verdict, trials: [], note: note, at: nil))
        }
        #expect(say(.notRun) == "Chưa thử.")
        #expect(say(.floor).hasPrefix("Dùng sàn tốc độ"))
        #expect(say(.forced).hasPrefix("Dùng tốc độ thủ công"))
        #expect(say(.none) == "Không cách nào dùng được trên máy này.")
        #expect(say(.inconclusive, note: "Thử lại khi máy nguội.") == "Thử lại khi máy nguội.")
        #expect(say(.inconclusive) == "Chưa kết luận được.")
    }

    @Test func eachTrialHasALineWithTheNumbers() {
        let ok = MechanismTrial(
            mechanism: .floor, accepted: true, detail: "", baselineRPM: 2100, requestedRPM: 3600, peakRPM: 3550, changed: true, heldAsAsked: true,
            modeAfter: 0, targetAfter: 2100, rpmAfter: 2300, restored: true
        )
        let refused = MechanismTrial(
            mechanism: .forced, accepted: false, detail: "the SMC refused F0Md (0x82)", baselineRPM: 2100, requestedRPM: 3600, peakRPM: 2100,
            changed: false, heldAsAsked: true, modeAfter: 0, targetAfter: 2100, rpmAfter: 2100, restored: true
        )
        let lines = FanProbePresentation.lines(FanProbeOutcome(verdict: .none, trials: [ok, refused], note: "", at: nil))
        #expect(lines[0] == "Sàn tốc độ: yêu cầu 3600, tốc độ lên 3550 từ 2100; giữ đúng mức đã đặt: có; trả về tự động: được.")
        #expect(lines[1] == "Tốc độ thủ công: helper không nhận lệnh (the SMC refused F0Md (0x82)).")
    }

    @Test func theOutcomeSurvivesBeingStoredAsSettings() throws {
        let outcome = FanProbeOutcome(
            verdict: .forced,
            trials: [MechanismTrial(
                mechanism: .forced, accepted: true, detail: "", baselineRPM: 2100, requestedRPM: 3600, peakRPM: 3500, changed: true, heldAsAsked: true,
                modeAfter: 0, targetAfter: 2100, rpmAfter: nil, restored: true
            )],
            note: "x", at: Date(timeIntervalSinceReferenceDate: 99)
        )
        let decoded = try JSONDecoder().decode(FanProbeOutcome.self, from: JSONEncoder().encode(outcome))
        #expect(decoded == outcome)
        #expect(FanProbeOutcome.never.verdict == .notRun && FanProbeOutcome.never.mechanism == nil)
    }
}
