import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct MenuBarClockPassageTests {
    private final class Rig {
        let scheduler = ManualScheduler()
        var panelOpen = false
        var restricted = true
        /// How many polls after the replay the panel shows; nil never.
        var opensAfterPolls: Int? = 0
        private(set) var log: [String] = []
        private(set) var passage: MenuBarClockPassage!
        private var polls = 0

        init() {
            passage = MenuBarClockPassage(
                scheduler: scheduler,
                isPanelOpen: { [unowned self] in
                    if log.last == "replay", let after = opensAfterPolls {
                        polls += 1
                        if polls > after { panelOpen = true }
                    }
                    return panelOpen
                },
                suspend: { [unowned self] in
                    guard restricted else { return false }
                    log.append("suspend")
                    return true
                },
                resume: { [unowned self] in log.append("resume") },
                replay: { [unowned self] in log.append("replay") }
            )
        }
    }

    @Test func theClickIsHeldTheBarGivenBackAndOneClickReplayedLater() {
        let rig = Rig()
        #expect(rig.passage.clockPressed())
        #expect(rig.log == ["suspend"])
        rig.scheduler.advance(by: MenuBarClockPassage.replayDelay - .milliseconds(1))
        #expect(rig.log == ["suspend"])
        rig.scheduler.advance(by: .milliseconds(1))
        #expect(rig.log.first(where: { $0 == "replay" }) != nil)
    }

    @Test func theRestrictionComesBackOnceThePanelShows() {
        let rig = Rig()
        rig.opensAfterPolls = 4
        _ = rig.passage.clockPressed()
        rig.scheduler.advance(by: MenuBarClockPassage.replayDelay + MenuBarClockPassage.pollInterval * 3)
        #expect(rig.log == ["suspend", "replay"])
        rig.scheduler.advance(by: MenuBarClockPassage.pollInterval)
        #expect(rig.log == ["suspend", "replay", "resume"])
        #expect(!rig.passage.isPassing)
    }

    @Test func aPanelThatNeverShowsGetsTheRestrictionBackAfterTheTimeout() {
        let rig = Rig()
        rig.opensAfterPolls = nil
        _ = rig.passage.clockPressed()
        rig.scheduler.advance(by: MenuBarClockPassage.replayDelay + MenuBarClockPassage.openTimeout - MenuBarClockPassage.pollInterval)
        #expect(rig.log == ["suspend", "replay"])
        rig.scheduler.advance(by: MenuBarClockPassage.pollInterval)
        #expect(rig.log == ["suspend", "replay", "resume"])
    }

    @Test func aClickWhileThePanelIsOpenClosesItAndIsLetThrough() {
        let rig = Rig()
        rig.panelOpen = true
        #expect(!rig.passage.clockPressed())
        #expect(rig.log.isEmpty)
    }

    @Test func withNothingRestrictedTheClickIsLetThrough() {
        let rig = Rig()
        rig.restricted = false
        #expect(!rig.passage.clockPressed())
        rig.scheduler.advance(by: .seconds(2))
        #expect(rig.log.isEmpty)
    }

    @Test func aSecondClickDuringAPassIsLetThrough() {
        let rig = Rig()
        #expect(rig.passage.clockPressed())
        #expect(!rig.passage.clockPressed())
        #expect(rig.log == ["suspend"])
    }

    @Test func aCancelledPassReplaysNothingAndLeavesTheRestrictionAlone() {
        let rig = Rig()
        _ = rig.passage.clockPressed()
        rig.passage.cancel()
        rig.scheduler.advance(by: .seconds(2))
        #expect(rig.log == ["suspend"])
        #expect(!rig.passage.isPassing)
    }
}
