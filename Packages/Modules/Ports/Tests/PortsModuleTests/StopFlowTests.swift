import Foundation
import Testing
@testable import PortsModule

@Suite struct StopFlowTests {
    let node = PortEntry.make(port: 3000, process: .make(pid: 10, name: "node", startTime: 1_000))
    let python = PortEntry.make(port: 8000, process: .make(pid: 11, name: "Python", command: "python3 -m http.server", startTime: 2_000))

    func phase(_ rig: Rig, _ pid: Int32 = 10) -> StopPhase? { rig.state.flows[pid]?.phase }

    // MARK: Asking

    @Test func askingSendsNothingAndCancellingSendsNothing() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.module.requestStop(node)
        #expect(phase(rig) == .confirming)
        #expect(rig.state.flows[10]?.message == "Dừng node (cổng 3000)?", "it names the process and the port")
        #expect(rig.state.needsAnswer)
        rig.module.cancelStop(pid: 10)
        #expect(rig.state.flows.isEmpty)
        #expect(rig.control.sent.isEmpty)
    }

    @Test func confirmingWithoutHavingAskedSendsNothing() async {
        let rig = await Rig([node])
        await rig.showTab()
        await rig.module.confirmStop(pid: 10)
        await rig.module.forceStop(pid: 10)
        #expect(rig.control.sent.isEmpty)
    }

    @Test func theQuestionNamesTheProcessAndNotOnlyTheAppItBelongsTo() async {
        // Stopping Docker's backend takes every container with it; "Docker" alone would not say that this is what is stopped.
        let backend = PortEntry.make(
            port: 5432,
            process: .make(pid: 30, name: "com.docker.backend", command: nil, path: "/Applications/Docker.app/Contents/MacOS/com.docker.backend")
        )
        let rig = await Rig([backend])
        await rig.showTab()
        rig.module.requestStop(backend)
        #expect(rig.state.flows[30]?.message == "Dừng com.docker.backend của Docker (cổng 5432)?")
        await rig.module.confirmStop(pid: 30)
        #expect(rig.state.flows[30]?.message == "Đang dừng com.docker.backend của Docker (cổng 5432)…")
        rig.source.set([])
        await rig.advance(3)
        #expect(rig.state.notice == "Đã dừng com.docker.backend của Docker (cổng 5432)")
        #expect(rig.control.signals == [.terminate])
    }

    @Test func aProcessNamedLikeItsAppIsNamedOnce() {
        #expect(PortProcess.make(name: "Python", path: "/Library/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python").fullName == "Python")
        #expect(PortProcess.make().fullName == "node")
        #expect(PortProcess.make(name: "Code Helper (Renderer)", path: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Renderer).app/Contents/MacOS/Code Helper (Renderer)").fullName
            == "Code Helper (Renderer) của Visual Studio Code")
    }

    // MARK: SIGTERM, then the offer

    @Test func yesSendsSIGTERMAndAfterThreeSecondsOffersSIGKILLWithoutSendingIt() async {
        let rig = await Rig([node])
        rig.control.ignore(.terminate, pid: 10)   // a server that traps SIGTERM
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        #expect(rig.control.signals == [.terminate])
        #expect(phase(rig) == .stopping)
        #expect(rig.state.flows[10]?.message == "Đang dừng node (cổng 3000)…")
        #expect(!rig.state.needsAnswer, "nothing to answer while waiting")

        await rig.advance(2.9)
        #expect(phase(rig) == .stopping)
        await rig.advance(0.1)
        #expect(phase(rig) == .stillRunning)
        #expect(rig.state.flows[10]?.message == "node (cổng 3000) chưa thoát.")
        #expect(rig.state.needsAnswer)
        #expect(rig.control.signals == [.terminate], "the offer is not the signal")

        await rig.advance(60)
        #expect(rig.control.signals == [.terminate], "and it never sends itself")
    }

    @Test func clickingBuocDungSendsSIGKILLAndThenTheProcessIsReportedStopped() async {
        let rig = await Rig([node])
        rig.control.ignore(.terminate, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        await rig.advance(3)
        rig.source.set([])

        await rig.module.forceStop(pid: 10)
        #expect(rig.control.signals == [.terminate, .kill])
        #expect(phase(rig) == .forcing)
        await rig.advance(1)
        #expect(rig.state.flows.isEmpty)
        #expect(rig.state.notice == "Đã dừng node (cổng 3000)")
        #expect(rig.state.entries.isEmpty, "the list is read again at once")
    }

    @Test func aProcessThatLeavesOnSIGTERMNeedsNoOffer() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        rig.source.set([])
        await rig.advance(3)
        #expect(rig.state.flows.isEmpty)
        #expect(rig.state.notice == "Đã dừng node (cổng 3000)")
        #expect(rig.control.signals == [.terminate])
        #expect(rig.state.entries.isEmpty)
    }

    @Test func theNoticeGoesAwayAfterAWhile() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        await rig.advance(3)
        #expect(rig.state.notice != nil)
        await rig.advance(4)
        #expect(rig.state.notice == nil)
    }

    @Test func aSecondClickWhileTheSignalIsOnItsWayDoesNotSendTwice() async {
        let rig = await Rig([node])
        rig.control.ignore(.terminate, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        let first = Task { await rig.module.confirmStop(pid: 10) }
        let second = Task { await rig.module.confirmStop(pid: 10) }
        await first.value
        await second.value
        #expect(rig.control.signals == [.terminate])
    }

    @Test func askingAgainWhileAStopIsRunningChangesNothing() async {
        let rig = await Rig([node])
        rig.control.ignore(.terminate, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        rig.module.requestStop(node)
        #expect(phase(rig) == .stopping)
        rig.module.cancelStop(pid: 10)
        #expect(phase(rig) == .stopping, "a stop that is running cannot be cancelled away")
    }

    @Test func twoProcessesCanBeStoppedAtOnce() async {
        let rig = await Rig([node, python])
        rig.control.ignore(.terminate, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        rig.module.requestStop(python)
        await rig.module.confirmStop(pid: 10)
        await rig.module.confirmStop(pid: 11)
        #expect(rig.control.sent.map(\.pid) == [10, 11])
        rig.source.set([node])
        await rig.advance(3)
        #expect(phase(rig, 10) == .stillRunning)
        #expect(phase(rig, 11) == nil, "Python left")
    }

    // MARK: Refusals

    @Test func stoppingIsRefusedForForeignRootOwnAppPidOneAndSystemProcesses() async {
        let others = [
            PortEntry.make(port: 4001, process: .make(pid: 20, name: "other", uid: 502)),
            PortEntry.make(port: 4002, process: .make(pid: 21, name: "rootd", uid: 0, path: "/opt/tool/rootd")),
            PortEntry.make(port: 4003, process: .make(pid: 700, name: "MyNotch", path: "/Applications/MyNotch.app/Contents/MacOS/MyNotch")),
            PortEntry.make(port: 4004, process: .make(pid: 1, name: "launchd", path: "/sbin/launchd")),
            PortEntry.make(port: 4005, process: .make(pid: 22, name: "ControlCenter", path: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter")),
        ]
        let expected: [StopRefusal] = [.otherUser, .root, .ownApp, .launchd, .system]
        let rig = await Rig(others)
        await rig.showTab()
        for (entry, refusal) in zip(others, expected) {
            #expect(!rig.module.actions.canStop(entry), "\(entry.process.name) has no Dừng button")
            rig.module.requestStop(entry)
            #expect(rig.state.flows[entry.pid]?.phase == .refused(refusal), "\(entry.process.name)")
            await rig.module.confirmStop(pid: entry.pid)
            await rig.module.forceStop(pid: entry.pid)
            await rig.advance(5)
        }
        #expect(rig.control.sent.isEmpty, "nothing was sent to any of them")
        #expect(!rig.state.flows.isEmpty)
        for entry in others { rig.module.cancelStop(pid: entry.pid) }
        #expect(rig.state.flows.isEmpty)
    }

    @Test func aRowThatMayBeStoppedHasTheButton() async {
        let rig = await Rig([node])
        #expect(rig.module.actions.canStop(node))
    }

    @Test func aProcessThatBecameRootOrSystemBetweenTheRowAndTheClickIsNotSignalled() async {
        let rig = await Rig([node, python])
        await rig.showTab()
        rig.control.add(.make(pid: 10, uid: 0, startTime: 1_000))   // same process, now root's (path and start time as shown)
        rig.control.add(.make(pid: 11, startTime: 2_000, path: "/usr/libexec/other"))
        rig.module.requestStop(node)
        rig.module.requestStop(python)
        await rig.module.confirmStop(pid: 10)
        await rig.module.confirmStop(pid: 11)
        #expect(phase(rig, 10) == .refused(.root))
        #expect(phase(rig, 11) == .failed(.changed), "its executable is not the one that was shown")
        #expect(rig.control.sent.isEmpty)
    }

    @Test func aPidThatNowBelongsToAnotherProcessIsNotSignalled() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.module.requestStop(node)
        rig.control.add(.make(pid: 10, startTime: 9_999))   // the pid was reused after the row was read
        await rig.module.confirmStop(pid: 10)
        #expect(phase(rig) == .failed(.changed))
        #expect(rig.state.flows[10]?.message == StopFailure.changed.message)
        #expect(rig.control.sent.isEmpty)
    }

    @Test func aPidReusedDuringTheGraceIsNotOfferedSIGKILL() async {
        let rig = await Rig([node])
        rig.control.ignore(.terminate, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        rig.control.add(.make(pid: 10, startTime: 9_999))   // the process left and another took its pid
        await rig.advance(3)
        #expect(rig.state.flows.isEmpty, "gone, not still running")
        #expect(rig.control.signals == [.terminate])
    }

    @Test func aPidReusedBeforeTheKillIsNotKilled() async {
        let rig = await Rig([node])
        rig.control.ignore(.terminate, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        await rig.advance(3)
        #expect(phase(rig) == .stillRunning)
        rig.control.add(.make(pid: 10, startTime: 9_999))
        await rig.module.forceStop(pid: 10)
        #expect(phase(rig) == .failed(.changed))
        #expect(rig.control.signals == [.terminate])
    }

    @Test func aProcessAlreadyGoneWhenTheUserSaysYesIsReportedAsStopped() async {
        let rig = await Rig([node])
        await rig.showTab()
        rig.module.requestStop(node)
        rig.control.remove(10)
        await rig.module.confirmStop(pid: 10)
        #expect(rig.state.flows.isEmpty)
        #expect(rig.state.notice == "Đã dừng node (cổng 3000)")
        #expect(rig.control.sent.isEmpty)
    }

    // MARK: Failures

    @Test func aSignalTheSystemRefusesIsReported() async {
        let rig = await Rig([node])
        rig.control.answer(.denied)
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        #expect(phase(rig) == .failed(.denied))
        #expect(rig.scheduler.pendingCount == 1, "only the poll is waiting, not a check of a stop that never started")
    }

    @Test func aProcessThatSurvivesSIGKILLIsCalledStuck() async {
        let rig = await Rig([node])
        rig.control.ignore(.terminate, pid: 10)
        rig.control.ignore(.kill, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        await rig.advance(3)
        await rig.module.forceStop(pid: 10)
        await rig.advance(1)
        #expect(phase(rig) == .failed(.stuck))
        #expect(rig.control.signals == [.terminate, .kill])
        rig.module.cancelStop(pid: 10)
        #expect(rig.state.flows.isEmpty)
    }

    // MARK: The tab going away

    @Test func closingTheTabDropsQuestionsButNotAStopInProgress() async {
        let rig = await Rig([node, python])
        rig.control.ignore(.terminate, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        rig.module.requestStop(python)
        await rig.module.confirmStop(pid: 10)
        rig.module.tabDisappeared()
        #expect(phase(rig, 10) == .stopping)
        #expect(phase(rig, 11) == nil, "an unanswered question is not left for the next time")
        #expect(rig.control.signals == [.terminate])
    }

    @Test func aStopThatTimesOutWithTheTabClosedLeavesNoStaleOffer() async {
        let rig = await Rig([node])
        rig.control.ignore(.terminate, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        rig.module.tabDisappeared()
        await rig.advance(3)
        #expect(rig.state.flows.isEmpty)
        #expect(rig.control.signals == [.terminate])
        #expect(rig.source.reads == 1, "and nothing is read while the tab is closed")
    }

    @Test func aQuestionAboutARowThatDisappearedIsDropped() async {
        let rig = await Rig([node, python])
        await rig.showTab()
        rig.module.requestStop(node)
        rig.source.set([python])
        await rig.advance(2)
        #expect(rig.state.flows.isEmpty)
    }

    @Test func switchingTheModuleOffDuringTheGraceSendsNothingMore() async {
        let rig = await Rig([node])
        rig.control.ignore(.terminate, pid: 10)
        await rig.showTab()
        rig.module.requestStop(node)
        await rig.module.confirmStop(pid: 10)
        await rig.harness.registry.setEnabled(false, for: "ports")
        await rig.advance(10)
        #expect(rig.control.signals == [.terminate])
        #expect(rig.state.flows.isEmpty)
    }

    // MARK: What the tab keeps open

    @Test func aQuestionOnARowTheFilterHidesDoesNotHoldTheNotchOpen() async {
        let rig = await Rig([node, python])
        await rig.showTab()
        rig.module.requestStop(node)
        #expect(rig.state.needsAnswer)
        rig.state.filter = "python"
        #expect(!rig.state.needsAnswer, "nobody can see the question")
        rig.state.filter = ""
        #expect(rig.state.needsAnswer, "and it is there again when the row is")
    }

    @Test func theNotchStaysPinnedForAQuestionAndForTypingOnly() {
        #expect(PortsTabView.pinsNotch(typing: true, needsAnswer: false))
        #expect(PortsTabView.pinsNotch(typing: false, needsAnswer: true))
        #expect(!PortsTabView.pinsNotch(typing: false, needsAnswer: false))
    }

    @Test func everyPhaseSaysWhetherItWaitsForTheUser() {
        #expect(StopPhase.confirming.needsAnswer)
        #expect(StopPhase.stillRunning.needsAnswer)
        #expect(StopPhase.refused(.root).needsAnswer)
        #expect(StopPhase.failed(.denied).needsAnswer)
        #expect(!StopPhase.stopping.needsAnswer)
        #expect(!StopPhase.forcing.needsAnswer)
        #expect(StopPhase.stopping.isBusy && StopPhase.forcing.isBusy)
        #expect(!StopPhase.confirming.isBusy && !StopPhase.stillRunning.isBusy)
    }

    @Test func theGraceIsThreeSecondsAndTheKillGraceOne() {
        #expect(StopFlow.grace == .seconds(3))
        #expect(StopFlow.killGrace == .seconds(1))
    }
}
