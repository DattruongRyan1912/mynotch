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
    }

    private struct State {
        var rpm: Double
        let apple: Double
        let maximum: Double
        var mode = 0.0
        var target: Double
        var floorActive = false
        var behaviour: Behaviour
        var commands: [FakeFanHelperClient.Command] = []
        var errorOnCommand: Int?
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
            if state.behaviour.failReading { throw FanHelperError.timeout }
            let heldAt = state.mode == 1 || state.floorActive ? state.target : state.apple
            state.rpm += 0.6 * (heldAt - state.rpm)
            return [
                FanHelperFanInfo(index: 0, rpm: state.rpm, minRPM: 1200, maxRPM: state.maximum, mode: state.mode, target: state.target),
                FanHelperFanInfo(index: 1, rpm: state.apple, minRPM: 1200, maxRPM: state.maximum, mode: 0, target: state.apple),
            ]
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
            state.mode = state.behaviour.forcedWorks ? 1 : 0
            state.target = rpm
            return FanCommandResult(ok: true, state: .forced, appliedRPM: rpm, leaseSeconds: 15)
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

@Suite struct FanProbeTests {
    /// The pauses a probe asked for, instead of waiting them.
    @MainActor final class Pauses {
        var durations: [Duration] = []
    }

    @MainActor func probe(_ client: SimulatedFanClient, _ pauses: Pauses = Pauses()) -> FanControlProbe {
        FanControlProbe(client: client, pause: { pauses.durations.append($0) }, now: { Date(timeIntervalSinceReferenceDate: 7) })
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
                changed: usable, modeAfter: 0, targetAfter: 2000, rpmAfter: 2000, restored: true
            )
        }
        #expect(FanProbeJudge.verdict(for: [trial(.floor, usable: true), trial(.forced, usable: true)]) == .floor)
        #expect(FanProbeJudge.verdict(for: [trial(.floor, usable: false), trial(.forced, usable: true)]) == .forced)
        #expect(FanProbeJudge.verdict(for: [trial(.floor, usable: false), trial(.forced, usable: false)]) == .none)
    }

    @Test func aWayThatDidNotRestoreIsNotUsableEvenIfItChangedTheSpeed() {
        let trial = MechanismTrial(
            mechanism: .floor, accepted: true, detail: "", baselineRPM: 2000, requestedRPM: 3500, peakRPM: 3400, changed: true,
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
            .forced(0, 3600), .forced(0, 3600), .forced(0, 3600), .auto(0), .auto(-1),
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
            mechanism: .floor, accepted: true, detail: "", baselineRPM: 2100, requestedRPM: 3600, peakRPM: 3550, changed: true,
            modeAfter: 0, targetAfter: 2100, rpmAfter: 2300, restored: true
        )
        let refused = MechanismTrial(
            mechanism: .forced, accepted: false, detail: "the SMC refused F0Md (0x82)", baselineRPM: 2100, requestedRPM: 3600, peakRPM: 2100,
            changed: false, modeAfter: 0, targetAfter: 2100, rpmAfter: 2100, restored: true
        )
        let lines = FanProbePresentation.lines(FanProbeOutcome(verdict: .none, trials: [ok, refused], note: "", at: nil))
        #expect(lines[0] == "Sàn tốc độ: yêu cầu 3600, tốc độ lên 3550 từ 2100; trả về tự động: được.")
        #expect(lines[1] == "Tốc độ thủ công: helper không nhận lệnh (the SMC refused F0Md (0x82)).")
    }

    @Test func theOutcomeSurvivesBeingStoredAsSettings() throws {
        let outcome = FanProbeOutcome(
            verdict: .forced,
            trials: [MechanismTrial(
                mechanism: .forced, accepted: true, detail: "", baselineRPM: 2100, requestedRPM: 3600, peakRPM: 3500, changed: true,
                modeAfter: 0, targetAfter: 2100, rpmAfter: nil, restored: true
            )],
            note: "x", at: Date(timeIntervalSinceReferenceDate: 99)
        )
        let decoded = try JSONDecoder().decode(FanProbeOutcome.self, from: JSONEncoder().encode(outcome))
        #expect(decoded == outcome)
        #expect(FanProbeOutcome.never.verdict == .notRun && FanProbeOutcome.never.mechanism == nil)
    }
}
