import ServiceManagement
import Testing
@testable import PerformanceModule

@Suite struct FanHelperPolicyTests {
    typealias Policy = FanHelperUpdatePolicy

    func decide(
        _ status: FanHelperRegistrationStatus = .enabled, running: FanHelperInfo? = .matching, bundled: BundledFanHelper = .matching,
        tried: Bool = false
    ) -> FanHelperUpdateAction {
        Policy.decide(status: status, running: running, bundled: bundled, alreadyTried: tried)
    }

    // MARK: The decision

    @Test func theHelperThatIsTheBundledOneIsLeftAlone() {
        #expect(decide() == .nothing)
    }

    @Test func aHelperOfAnotherVersionIsRegisteredAgain() {
        #expect(decide(running: FanHelperInfo(version: "0", buildID: "aaaa", euid: 0, pid: 1)) == .reRegister)
    }

    @Test func aHelperOfAnotherBuildIsRegisteredAgain() {
        #expect(decide(running: .oldBuild) == .reRegister)
    }

    @Test func aVersionThatChangedIsEnoughEvenWhenTheBundledBuildCannotBeRead() {
        #expect(decide(running: FanHelperInfo(version: "0", buildID: "aaaa", euid: 0, pid: 1), bundled: BundledFanHelper(version: "1", buildID: nil)) == .reRegister)
    }

    @Test func whenTheBundledBuildCannotBeReadOnlyTheVersionCounts() {
        #expect(decide(running: .oldBuild, bundled: BundledFanHelper(version: "1", buildID: nil)) == .nothing)
    }

    @Test func aHelperThatDoesNotKnowItsOwnBuildIsJudgedByVersionAlone() {
        for unknown in ["", "unknown"] {
            #expect(decide(running: FanHelperInfo(version: "1", buildID: unknown, euid: 0, pid: 1)) == .nothing, "\(unknown)")
        }
    }

    @Test func aSecondAttemptInTheSameLaunchIsNeverMade() {
        #expect(decide(running: .oldBuild, tried: true) == .nothing)
    }

    @Test func aHelperThatDidNotAnswerIsNotRetriedInALoop() {
        #expect(decide(running: nil) == .nothing)
    }

    @Test func aHelperThatIsNotEnabledIsNotTouchedWhateverTheMismatch() {
        for status in [FanHelperRegistrationStatus.notRegistered, .requiresApproval, .notFound] {
            #expect(decide(status, running: .oldBuild) == .nothing, "\(status)")
        }
    }

    @Test func outdatedMeansAnotherVersionOrAnotherKnownBuild() {
        #expect(Policy.isOutdated(.matching, bundled: .matching) == false)
        #expect(Policy.isOutdated(.oldBuild, bundled: .matching))
        #expect(Policy.isOutdated(FanHelperInfo(version: "2", buildID: "aaaa", euid: 0, pid: 1), bundled: .matching))
    }

    // MARK: The system's status

    @Test func eachStatusOfTheServiceManagerMapsToOurs() {
        #expect(FanHelperRegistrationStatus(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(FanHelperRegistrationStatus(SMAppService.Status.enabled) == .enabled)
        #expect(FanHelperRegistrationStatus(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(FanHelperRegistrationStatus(SMAppService.Status.notFound) == .notFound)
    }

    @Test func aStatusFromANewerSystemIsTakenAsNotFoundNotAsRunning() throws {
        let future = try #require(SMAppService.Status(rawValue: 99))
        #expect(FanHelperRegistrationStatus(future) == .notFound)
    }

    // MARK: What the UI says

    func say(_ phase: FanHelperPhase, mfc: Bool = false) -> FanHelperPresentation {
        FanHelperPresentation(phase: phase, macsFanControlRunning: mfc)
    }

    @Test func notInstalledSaysSoAndOffersToInstall() {
        let p = say(.notInstalled)
        #expect(p.status == "Chưa cài" && p.shortStatus == "chưa cài")
        #expect(p.primary == .install && p.canUninstall == false && p.tone == nil && p.isBusy == false)
        #expect(FanHelperAction.install.title == "Cài helper điều khiển quạt")
    }

    @Test func waitingForApprovalSendsTheUserToSystemSettingsAndCanBeRemoved() {
        let p = say(.needsApproval)
        #expect(p.status == "Cần cho phép trong Cài đặt hệ thống")
        #expect(p.primary == .openSettings && p.canUninstall && p.tone == .caution)
        #expect(FanHelperAction.openSettings.title == "Mở Cài đặt")
    }

    @Test func aRunningHelperSaysItsVersionAndOnlyOffersToBeRemoved() {
        let p = say(.running(.matching))
        #expect(p.status == "Đang chạy (phiên bản 1, quyền root)" && p.shortStatus == "đang chạy")
        #expect(p.primary == nil && p.canUninstall && p.tone == .normal)
    }

    @Test func anErrorSaysWhatWentWrongAndOffersAnotherTryAndTheRemoval() {
        let failed = say(.failed("lý do"))
        #expect(failed.status == "Lỗi: lý do" && failed.shortStatus == "lỗi")
        #expect(failed.primary == .retry && failed.canUninstall && failed.tone == .critical)
        let unreachable = say(.unreachable("helper không trả lời"))
        #expect(unreachable.status == "Lỗi: không kết nối được helper (helper không trả lời)")
        #expect(unreachable.primary == .retry)
    }

    @Test func aHelperThatIsNotInTheAppIsAnErrorWithNothingToPress() {
        let p = say(.notFound)
        #expect(p.status == "Lỗi: không tìm thấy helper trong ứng dụng")
        #expect(p.primary == nil && p.canUninstall == false)
    }

    @Test func whileBusyNothingCanBePressed() {
        for (busy, text) in [(FanHelperBusy.installing, "Đang cài…"), (.removing, "Đang gỡ…"), (.updating, "Đang cập nhật helper…")] {
            let p = say(.busy(busy))
            #expect(p.status == text && p.isBusy && p.primary == nil && p.canUninstall == false, "\(busy)")
        }
    }

    @Test func beforeTheFirstLookItSaysItIsLooking() {
        let p = say(.unknown)
        #expect(p.status == "Đang kiểm tra…" && p.primary == nil && p.canUninstall == false)
    }

    @Test func macsFanControlRunningAddsTheWarningWhateverTheState() {
        for phase in [FanHelperPhase.notInstalled, .running(.matching), .needsApproval] {
            #expect(say(phase, mfc: true).warning == "Thoát Macs Fan Control trước khi điều khiển quạt")
            #expect(say(phase, mfc: false).warning == nil)
        }
    }

    @Test func theCompactTitlesFitTheTab() {
        #expect(FanHelperAction.install.compactTitle == "Cài helper")
        #expect(FanHelperAction.openSettings.compactTitle == "Cài đặt")
        #expect(FanHelperAction.retry.compactTitle == "Thử lại")
    }

    // MARK: The comparison

    @Test func theHelpersReadingIsShownBesideTheAppsOwn() {
        let app = [FanReading(index: 0, rpm: 5170, minRPM: 1200, maxRPM: 5779), FanReading(index: 1, rpm: 5632, minRPM: 1200, maxRPM: 6241)]
        let comparison = FanComparison(helper: FanHelperFanInfo.both, app: app)
        #expect(comparison.lines == [
            "Quạt 1: helper 5173 · app 5170 vòng/phút · tự động",
            "Quạt 2: helper 5636 · app 5632 vòng/phút · tự động",
        ])
        #expect(comparison.failure == nil)
    }

    @Test func aFanTheAppDidNotReadShowsADash() {
        let comparison = FanComparison(helper: FanHelperFanInfo.both, app: [])
        #expect(comparison.lines.first == "Quạt 1: helper 5173 · app — vòng/phút · tự động")
    }

    @Test func theFanModeIsNamed() {
        #expect(FanComparison.mode(0) == "tự động")
        #expect(FanComparison.mode(1) == "thủ công (1)")
        #expect(FanComparison.mode(3) == "thủ công (3)")
        #expect(FanComparison.mode(-1) == "chế độ không rõ")
    }

    @Test func aFailedReadHasNoLines() {
        let comparison = FanComparison(failure: "x")
        #expect(comparison.lines.isEmpty && comparison.failure == "x")
    }
}
